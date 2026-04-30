/*
 * Copyright (c) 2025 ADBC Drivers Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Apache.Arrow;
using Apache.Arrow.Adbc;
using Apache.Arrow.Ipc;
using Xunit;
using Xunit.Abstractions;

namespace AdbcDrivers.BigQuery.Perf
{
    /// <summary>
    /// Performance tests for the metadata path (Connection.GetObjects).
    /// Exercises the code paths used by BI tools / schema browsers, distinct
    /// from the data-import path measured by FullTableImportTest.
    /// </summary>
    public class GetObjectsTest
    {
        private readonly ITestOutputHelper _output;
        private readonly List<PerfTestEnvironment> _environments;

        public GetObjectsTest(ITestOutputHelper output)
        {
            _output = output;

            string? configPath = Environment.GetEnvironmentVariable(FullTableImportTest.PERF_CONFIG_VARIABLE);
            Skip.IfNot(
                !string.IsNullOrEmpty(configPath) && File.Exists(configPath),
                $"Performance tests require the {FullTableImportTest.PERF_CONFIG_VARIABLE} environment variable pointing to a valid config file.");

            string json = File.ReadAllText(configPath!);
            PerfTestConfiguration config = JsonSerializer.Deserialize<PerfTestConfiguration>(json)
                ?? throw new InvalidOperationException("Failed to deserialize perf config.");

            _environments = config.Environments;
        }

        private void Log(string message)
        {
            _output.WriteLine(message);
            Console.Error.WriteLine(message);
        }

        /// <summary>
        /// Quick metadata-path preflight: lists catalogs (depth=Catalogs) for each
        /// configured environment to verify credentials, network, and the ability
        /// to reach the metadata APIs before committing to a long suite.
        /// </summary>
        [SkippableFact]
        public async Task VerifyMetadataConnectivity()
        {
            bool allOk = true;

            foreach (PerfTestEnvironment env in _environments)
            {
                Log($"Metadata connectivity check: {env.Name} ...");
                try
                {
                    Stopwatch sw = Stopwatch.StartNew();
                    Dictionary<string, string> parameters = FullTableImportTest.BuildParameters(env);
                    AdbcDatabase database = new BigQueryDriver().Open(parameters);
                    using AdbcConnection connection = database.Connect(new Dictionary<string, string>());

                    long catalogs = 0;
                    using (IArrowArrayStream stream = connection.GetObjects(
                        depth: GetObjectsDepth.Catalogs,
                        catalogPattern: NullIfEmpty(env.Catalog),
                        dbSchemaPattern: null,
                        tableNamePattern: null,
                        tableTypes: null,
                        columnNamePattern: null))
                    {
                        while (true)
                        {
                            RecordBatch? batch = await stream.ReadNextRecordBatchAsync();
                            if (batch == null) break;
                            catalogs += batch.Length;
                        }
                    }
                    sw.Stop();
                    Log($"  ✅ {env.Name}: OK ({catalogs} catalogs, {sw.Elapsed.TotalSeconds:F1}s)");
                }
                catch (Exception ex)
                {
                    Log($"  ❌ {env.Name}: {ex.GetType().Name}: {ex.Message}");
                    allOk = false;
                }
            }

            Assert.True(allOk, "One or more environments failed the metadata connectivity check. See output for details.");
        }

        /// <summary>
        /// Calls GetObjects(depth=All) for each configured environment and measures
        /// connection time, time-to-first-batch, total wall-clock, batch count, and
        /// peak working set. Filters by env.Catalog and env.Schema (when non-empty)
        /// so the test scope is bounded; unset both for a full account-wide crawl.
        /// </summary>
        [SkippableFact]
        public async Task MeasureGetObjects()
        {
            foreach (PerfTestEnvironment env in _environments)
            {
                Log("==========================================================");
                Log($"Environment: {env.Name}");
                Log($"Catalog pattern: {env.Catalog ?? "(all)"}");
                Log($"Schema pattern:  {(string.IsNullOrEmpty(env.Schema) ? "(all)" : env.Schema!)}");
                Log("==========================================================");

                Stopwatch totalSw = Stopwatch.StartNew();

                // Phase 1: Connect
                Stopwatch connectSw = Stopwatch.StartNew();
                Dictionary<string, string> parameters = FullTableImportTest.BuildParameters(env);
                AdbcDatabase database = new BigQueryDriver().Open(parameters);
                using AdbcConnection connection = database.Connect(new Dictionary<string, string>());
                connectSw.Stop();
                Log($"Connection time: {connectSw.Elapsed}");

                // Force a GC before sampling so the peak-working-set delta reflects
                // GetObjects allocations rather than residual JIT/loader overhead.
                GC.Collect();
                GC.WaitForPendingFinalizers();
                GC.Collect();

                long startWorkingSet = Process.GetCurrentProcess().WorkingSet64;
                long peakWorkingSet = startWorkingSet;

                // Phase 2: GetObjects(All) — single Stopwatch covers the whole streamed read
                Stopwatch getObjectsSw = Stopwatch.StartNew();
                Stopwatch firstBatchSw = Stopwatch.StartNew();
                TimeSpan timeToFirstBatch = TimeSpan.Zero;
                bool firstBatch = true;
                long totalBatches = 0;
                long totalRows = 0;
                int columnCount = 0;

                using (IArrowArrayStream stream = connection.GetObjects(
                    depth: GetObjectsDepth.All,
                    catalogPattern: NullIfEmpty(env.Catalog),
                    dbSchemaPattern: NullIfEmpty(env.Schema),
                    tableNamePattern: null,
                    tableTypes: null,
                    columnNamePattern: null))
                {
                    Schema arrowSchema = stream.Schema;
                    columnCount = arrowSchema.FieldsList.Count;
                    Log($"GetObjects schema columns: {columnCount}");

                    while (true)
                    {
                        RecordBatch? batch = await stream.ReadNextRecordBatchAsync();
                        if (batch == null) break;

                        if (firstBatch)
                        {
                            firstBatchSw.Stop();
                            timeToFirstBatch = firstBatchSw.Elapsed;
                            firstBatch = false;
                        }

                        totalBatches++;
                        totalRows += batch.Length;

                        long currentWs = Process.GetCurrentProcess().WorkingSet64;
                        if (currentWs > peakWorkingSet) peakWorkingSet = currentWs;
                    }
                }
                getObjectsSw.Stop();
                totalSw.Stop();

                long workingSetDelta = peakWorkingSet - startWorkingSet;

                // Results — line prefixes ("Total:", "Total catalogs:", etc.) are
                // scraped by run-metadata-perf-suite.sh; do not rename them
                // without updating that script in lockstep.
                Log("");
                Log("--- Timing ---");
                Log($"  Connection:        {connectSw.Elapsed}");
                Log($"  Time to 1st batch: {timeToFirstBatch}");
                Log($"  GetObjects total:  {getObjectsSw.Elapsed}");
                Log($"  Total:             {totalSw.Elapsed}");

                Log("");
                Log("--- Volume ---");
                Log($"  Total catalogs:    {totalRows:N0}");
                Log($"  Total batches:     {totalBatches:N0}");
                Log($"  Schema columns:    {columnCount}");

                Log("");
                Log("--- Memory ---");
                Log($"  Start working set: {FormatBytes(startWorkingSet)}");
                Log($"  Peak working set:  {FormatBytes(peakWorkingSet)}");
                Log($"  Working set delta: {FormatBytes(workingSetDelta)}");

                Log("==========================================================");
                Log("");
            }
        }

        /// <summary>
        /// Runs GetObjects(All) for each environment N times (N = env.Iterations or
        /// 5 by default) and reports min/max/avg/stddev of duration plus peak working
        /// set across all iterations. The orchestrator (run-metadata-perf-suite.sh)
        /// uses the avg + stddev to compute Δ vs baseline ± stddev. Per-iteration
        /// lines and the "--- Summary ---" block follow the same shape as
        /// MeasureFullTableImportRepeated so the orchestrator's parser stays simple.
        /// </summary>
        [SkippableFact]
        public async Task MeasureGetObjectsRepeated()
        {
            foreach (PerfTestEnvironment env in _environments)
            {
                int iterations = env.Iterations > 0 ? env.Iterations : 5;

                Log("==========================================================");
                Log($"Environment: {env.Name}");
                Log($"Catalog pattern: {env.Catalog ?? "(all)"}");
                Log($"Schema pattern:  {(string.IsNullOrEmpty(env.Schema) ? "(all)" : env.Schema!)}");
                Log($"Iterations: {iterations}");
                Log("==========================================================");

                Dictionary<string, string> parameters = FullTableImportTest.BuildParameters(env);
                AdbcDatabase database = new BigQueryDriver().Open(parameters);
                using AdbcConnection connection = database.Connect(new Dictionary<string, string>());

                List<double> durations = new List<double>();
                List<long> catalogCounts = new List<long>();
                List<long> batchCounts = new List<long>();
                long peakWorkingSetAcrossRuns = 0;

                for (int i = 0; i < iterations; i++)
                {
                    Log("");
                    Log($"--- Run {i + 1}/{iterations} ---");

                    // Force a GC before sampling so the per-iteration peak reflects
                    // GetObjects allocations rather than residual heap from the
                    // previous iteration.
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect();

                    long startWs = Process.GetCurrentProcess().WorkingSet64;
                    long peakWs = startWs;

                    long iterCatalogs = 0;
                    long iterBatches = 0;

                    Stopwatch sw = Stopwatch.StartNew();
                    using (IArrowArrayStream stream = connection.GetObjects(
                        depth: GetObjectsDepth.All,
                        catalogPattern: NullIfEmpty(env.Catalog),
                        dbSchemaPattern: NullIfEmpty(env.Schema),
                        tableNamePattern: null,
                        tableTypes: null,
                        columnNamePattern: null))
                    {
                        while (true)
                        {
                            RecordBatch? batch = await stream.ReadNextRecordBatchAsync();
                            if (batch == null) break;
                            iterBatches++;
                            iterCatalogs += batch.Length;

                            long currentWs = Process.GetCurrentProcess().WorkingSet64;
                            if (currentWs > peakWs) peakWs = currentWs;
                        }
                    }
                    sw.Stop();

                    durations.Add(sw.Elapsed.TotalSeconds);
                    catalogCounts.Add(iterCatalogs);
                    batchCounts.Add(iterBatches);
                    if (peakWs > peakWorkingSetAcrossRuns) peakWorkingSetAcrossRuns = peakWs;

                    // Per-iteration line. Format mirrors MeasureFullTableImportRepeated
                    // ("  N rows, ..., Elapsed") but with metadata-specific units.
                    Log($"  {iterCatalogs:N0} catalogs, {iterBatches:N0} batches, {sw.Elapsed}, peak Δ {FormatBytes(peakWs - startWs)}");
                }

                // Summary — line prefixes match MeasureFullTableImportRepeated so
                // run-metadata-perf-suite.sh can reuse the same regex shapes.
                Log("");
                Log("--- Summary ---");
                Log($"  Avg duration:  {durations.Average():F2}s");
                Log($"  Min duration:  {durations.Min():F2}s");
                Log($"  Max duration:  {durations.Max():F2}s");
                if (durations.Count > 1)
                {
                    double mean = durations.Average();
                    double stddev = Math.Sqrt(durations.Select(d => (d - mean) * (d - mean)).Sum() / (durations.Count - 1));
                    Log($"  Std deviation: {stddev:F2}s");
                }
                Log($"  Avg catalogs:  {catalogCounts.Average():F0}");
                Log($"  Avg batches:   {batchCounts.Average():F0}");
                Log($"  Peak working set: {FormatBytes(peakWorkingSetAcrossRuns)}");
                Log("==========================================================");
                Log("");
            }
        }

        private static string? NullIfEmpty(string? value)
        {
            return string.IsNullOrEmpty(value) ? null : value;
        }

        private static string FormatBytes(long bytes)
        {
            string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
            int index = 0;
            double value = bytes;
            while (value >= 1024 && index < suffixes.Length - 1)
            {
                value /= 1024;
                index++;
            }
            return $"{value:F2} {suffixes[index]}";
        }
    }
}
