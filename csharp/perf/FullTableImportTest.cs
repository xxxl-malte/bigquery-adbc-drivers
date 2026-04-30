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
using Apache.Arrow.Adbc.Tests;
using Apache.Arrow.Ipc;
using Xunit;
using Xunit.Abstractions;

namespace AdbcDrivers.BigQuery.Perf
{
    /// <summary>
    /// Performance tests that measure full table import throughput.
    /// Requires BIGQUERY_PERF_CONFIG_FILE environment variable pointing to a JSON config file.
    /// </summary>
    public class FullTableImportTest
    {
        internal const string PERF_CONFIG_VARIABLE = "BIGQUERY_PERF_CONFIG_FILE";

        private readonly ITestOutputHelper _output;
        private readonly List<PerfTestEnvironment> _environments;

        public FullTableImportTest(ITestOutputHelper output)
        {
            _output = output;

            Skip.IfNot(
                !string.IsNullOrEmpty(Environment.GetEnvironmentVariable(PERF_CONFIG_VARIABLE))
                && File.Exists(Environment.GetEnvironmentVariable(PERF_CONFIG_VARIABLE)),
                $"Performance tests require the {PERF_CONFIG_VARIABLE} environment variable pointing to a valid config file.");

            string json = File.ReadAllText(Environment.GetEnvironmentVariable(PERF_CONFIG_VARIABLE)!);
            PerfTestConfiguration config = JsonSerializer.Deserialize<PerfTestConfiguration>(json)
                ?? throw new InvalidOperationException("Failed to deserialize perf config.");

            _environments = config.Environments;
        }

        /// <summary>
        /// Writes to both ITestOutputHelper and Console.Error so output is
        /// visible in Docker logs regardless of xUnit verbosity settings.
        /// </summary>
        private void Log(string message)
        {
            _output.WriteLine(message);
            Console.Error.WriteLine(message);
        }

        /// <summary>
        /// Reads all rows from the configured BigQuery table using SELECT * and measures
        /// connection time, query execution time, data transfer time, and total time.
        /// </summary>
        [SkippableFact]
        public async Task MeasureFullTableImport()
        {
            foreach (PerfTestEnvironment env in _environments)
            {
                Log("==========================================================");
                Log($"Environment: {env.Name}");
                Log($"Table: {env.Catalog}.{env.Schema}.{env.Table}");
                Log("==========================================================");

                Stopwatch totalSw = Stopwatch.StartNew();

                // Phase 1: Connect
                Stopwatch connectSw = Stopwatch.StartNew();
                Dictionary<string, string> parameters = BuildParameters(env);
                AdbcDatabase database = new BigQueryDriver().Open(parameters);
                using AdbcConnection connection = database.Connect(new Dictionary<string, string>());
                connectSw.Stop();
                Log($"Connection time: {connectSw.Elapsed}");

                // Phase 2: Execute query
                Stopwatch querySw = Stopwatch.StartNew();
                using AdbcStatement statement = connection.CreateStatement();

                string fullyQualifiedTable = $"`{env.Catalog}`.`{env.Schema}`.`{env.Table}`";
                statement.SqlQuery = $"SELECT * FROM {fullyQualifiedTable}";
                Log($"Query: {statement.SqlQuery}");

                QueryResult queryResult = statement.ExecuteQuery();
                querySw.Stop();
                Log($"Query execution time: {querySw.Elapsed}");

                // Phase 3: Read all data
                Stopwatch readSw = Stopwatch.StartNew();
                long totalRows = 0;
                long totalBatches = 0;
                long totalBytes = 0;
                int columnCount = 0;
                List<long> batchRowCounts = new List<long>();
                Stopwatch firstBatchSw = Stopwatch.StartNew();
                bool firstBatch = true;
                TimeSpan timeToFirstBatch = TimeSpan.Zero;

                using (IArrowArrayStream stream = queryResult.Stream!)
                {
                    Schema schema = stream.Schema;
                    columnCount = schema.FieldsList.Count;
                    Log($"Schema: {columnCount} columns");
                    foreach (Field field in schema.FieldsList)
                    {
                        Log($"  {field.Name}: {field.DataType.TypeId}");
                    }

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
                        batchRowCounts.Add(batch.Length);

                        // Estimate in-memory size from Arrow arrays
                        long batchBytes = EstimateBatchBytes(batch);
                        totalBytes += batchBytes;
                    }
                }
                readSw.Stop();
                totalSw.Stop();

                // Results
                Log("");
                Log("--- Timing ---");
                Log($"  Connection:       {connectSw.Elapsed}");
                Log($"  Query execution:  {querySw.Elapsed}");
                Log($"  Time to 1st batch:{timeToFirstBatch}");
                Log($"  Data transfer:    {readSw.Elapsed}");
                Log($"  Total:            {totalSw.Elapsed}");

                Log("");
                Log("--- Volume ---");
                Log($"  Total rows:       {totalRows:N0}");
                Log($"  Total batches:    {totalBatches:N0}");
                Log($"  Columns:          {columnCount}");
                Log($"  Total bytes (est):{totalBytes:N0} ({FormatBytes(totalBytes)})");

                if (batchRowCounts.Count > 0)
                {
                    Log($"  Avg batch size:   {batchRowCounts.Average():N0} rows");
                    Log($"  Min batch size:   {batchRowCounts.Min():N0} rows");
                    Log($"  Max batch size:   {batchRowCounts.Max():N0} rows");
                }

                Log("");
                Log("--- Throughput ---");
                double readSeconds = readSw.Elapsed.TotalSeconds;
                double totalSeconds = totalSw.Elapsed.TotalSeconds;
                if (readSeconds > 0)
                {
                    Log($"  Rows/sec (read):  {totalRows / readSeconds:N0}");
                    Log($"  Bytes/sec (read): {totalBytes / readSeconds:N0} ({FormatBytes((long)(totalBytes / readSeconds))}/s)");
                }
                if (totalSeconds > 0)
                {
                    Log($"  Rows/sec (total): {totalRows / totalSeconds:N0}");
                    Log($"  Bytes/sec (total):{totalBytes / totalSeconds:N0} ({FormatBytes((long)(totalBytes / totalSeconds))}/s)");
                }

                Log("==========================================================");
                Log("");
            }
        }

        /// <summary>
        /// Quick connectivity preflight: connects to each configured environment
        /// and executes SELECT 1 to verify credentials, network, and project access
        /// before committing to a full (potentially multi-hour) test suite.
        /// </summary>
        [SkippableFact]
        public async Task VerifyConnectivity()
        {
            bool allOk = true;

            foreach (PerfTestEnvironment env in _environments)
            {
                Log($"Connectivity check: {env.Name} ...");
                try
                {
                    Stopwatch sw = Stopwatch.StartNew();
                    Dictionary<string, string> parameters = BuildParameters(env);
                    AdbcDatabase database = new BigQueryDriver().Open(parameters);
                    using AdbcConnection connection = database.Connect(new Dictionary<string, string>());
                    using AdbcStatement statement = connection.CreateStatement();
                    statement.SqlQuery = "SELECT 1 AS connectivity_check";

                    QueryResult result = statement.ExecuteQuery();
                    using (IArrowArrayStream stream = result.Stream!)
                    {
                        RecordBatch? batch = await stream.ReadNextRecordBatchAsync();
                        if (batch == null || batch.Length == 0)
                        {
                            Log($"  ❌ {env.Name}: query returned no rows");
                            allOk = false;
                            continue;
                        }
                    }
                    sw.Stop();
                    Log($"  ✅ {env.Name}: OK ({sw.Elapsed.TotalSeconds:F1}s)");
                }
                catch (Exception ex)
                {
                    Log($"  ❌ {env.Name}: {ex.GetType().Name}: {ex.Message}");
                    allOk = false;
                }
            }

            Assert.True(allOk, "One or more environments failed the connectivity check. See output for details.");
        }

        /// <summary>
        /// Runs the same full table import multiple times and reports statistics
        /// to account for variance in network/server conditions.
        /// </summary>
        [SkippableFact]
        public async Task MeasureFullTableImportRepeated()
        {
            foreach (PerfTestEnvironment env in _environments)
            {
                int iterations = env.Iterations > 0 ? env.Iterations : 5;

                _output.WriteLine("==========================================================");
                _output.WriteLine($"Environment: {env.Name}");
                _output.WriteLine($"Table: {env.Catalog}.{env.Schema}.{env.Table}");
                _output.WriteLine($"Iterations: {iterations}");
                _output.WriteLine("==========================================================");

                List<double> durations = new List<double>();
                List<long> rowCounts = new List<long>();
                List<long> byteCounts = new List<long>();

                for (int i = 0; i < iterations; i++)
                {
                    _output.WriteLine($"--- Run {i + 1}/{iterations} ---");

                    Dictionary<string, string> parameters = BuildParameters(env);
                    AdbcDatabase database = new BigQueryDriver().Open(parameters);
                    using AdbcConnection connection = database.Connect(new Dictionary<string, string>());
                    using AdbcStatement statement = connection.CreateStatement();

                    string fullyQualifiedTable = $"`{env.Catalog}`.`{env.Schema}`.`{env.Table}`";
                    statement.SqlQuery = $"SELECT * FROM {fullyQualifiedTable}";

                    Stopwatch sw = Stopwatch.StartNew();
                    QueryResult queryResult = statement.ExecuteQuery();

                    long totalRows = 0;
                    long totalBytes = 0;

                    using (IArrowArrayStream stream = queryResult.Stream!)
                    {
                        while (true)
                        {
                            RecordBatch? batch = await stream.ReadNextRecordBatchAsync();
                            if (batch == null) break;

                            totalRows += batch.Length;
                            totalBytes += EstimateBatchBytes(batch);
                        }
                    }
                    sw.Stop();

                    durations.Add(sw.Elapsed.TotalSeconds);
                    rowCounts.Add(totalRows);
                    byteCounts.Add(totalBytes);

                    _output.WriteLine($"  {totalRows:N0} rows, {FormatBytes(totalBytes)}, {sw.Elapsed}");
                }

                _output.WriteLine("");
                _output.WriteLine("--- Summary ---");
                _output.WriteLine($"  Avg duration:  {durations.Average():F2}s");
                _output.WriteLine($"  Min duration:  {durations.Min():F2}s");
                _output.WriteLine($"  Max duration:  {durations.Max():F2}s");
                if (durations.Count > 1)
                {
                    double mean = durations.Average();
                    double stddev = Math.Sqrt(durations.Select(d => (d - mean) * (d - mean)).Sum() / (durations.Count - 1));
                    _output.WriteLine($"  Std deviation: {stddev:F2}s");
                }
                double avgBytes = byteCounts.Average();
                double avgDuration = durations.Average();
                if (avgDuration > 0)
                {
                    _output.WriteLine($"  Avg throughput:{FormatBytes((long)(avgBytes / avgDuration))}/s");
                }
                _output.WriteLine("==========================================================");
            }
        }

        internal static Dictionary<string, string> BuildParameters(PerfTestEnvironment env)
        {
            Dictionary<string, string> parameters = new Dictionary<string, string>();

            if (!string.IsNullOrEmpty(env.ProjectId))
                parameters["adbc.bigquery.project_id"] = env.ProjectId!;

            if (!string.IsNullOrEmpty(env.BillingProjectId))
                parameters["adbc.bigquery.billing_project_id"] = env.BillingProjectId!;

            switch (env.AuthenticationType?.ToLowerInvariant())
            {
                case "service":
                    parameters["adbc.bigquery.auth_type"] = "service";
                    parameters["adbc.bigquery.auth_json_credential"] = ResolveJsonCredential(env.JsonCredential);
                    break;
                case "user":
                    parameters["adbc.bigquery.auth_type"] = "user";
                    parameters["adbc.bigquery.client_id"] = env.ClientId ?? "";
                    parameters["adbc.bigquery.client_secret"] = env.ClientSecret ?? "";
                    parameters["adbc.bigquery.refresh_token"] = env.RefreshToken ?? "";
                    break;
                default:
                    if (!string.IsNullOrEmpty(env.JsonCredential))
                    {
                        parameters["adbc.bigquery.auth_type"] = "service";
                        parameters["adbc.bigquery.auth_json_credential"] = env.JsonCredential!;
                    }
                    else
                    {
                        // Fall back to GOOGLE_APPLICATION_CREDENTIALS
                        string? resolved = ResolveJsonCredential(null);
                        if (!string.IsNullOrEmpty(resolved))
                        {
                            parameters["adbc.bigquery.auth_type"] = "service";
                            parameters["adbc.bigquery.auth_json_credential"] = resolved;
                        }
                    }
                    break;
            }

            if (!string.IsNullOrEmpty(env.Scopes))
                parameters["adbc.bigquery.scopes"] = env.Scopes!;

            if (!string.IsNullOrEmpty(env.Location))
                parameters["adbc.bigquery.default_client_location"] = env.Location!;

            if (env.MaxStreamCount.HasValue)
                parameters["adbc.bigquery.max_fetch_concurrency"] = env.MaxStreamCount.Value.ToString();

            parameters["adbc.bigquery.large_decimals_as_string"] = "true";
            parameters["adbc.bigquery.include_constraints_getobjects"] = "false";
            parameters["adbc.bigquery.include_public_project_id"] = "false";
            parameters["adbc.bigquery.create_large_results_dataset"] = "true";

            if (env.AllowLargeResults)
            {
                parameters["adbc.bigquery.allow_large_results"] = "true";
                if (!string.IsNullOrEmpty(env.LargeResultsDataset))
                    parameters["adbc.bigquery.large_results_dataset"] = env.LargeResultsDataset!;
            }

            return parameters;
        }

        /// <summary>
        /// Resolves the JSON credential string. If the provided value is null/empty,
        /// falls back to reading the file pointed to by GOOGLE_APPLICATION_CREDENTIALS.
        /// </summary>
        private static string ResolveJsonCredential(string? jsonCredential)
        {
            if (!string.IsNullOrEmpty(jsonCredential))
                return jsonCredential!;

            string? credPath = Environment.GetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS");
            if (!string.IsNullOrEmpty(credPath) && File.Exists(credPath))
                return File.ReadAllText(credPath);

            throw new InvalidOperationException(
                "No JSON credential provided in config and GOOGLE_APPLICATION_CREDENTIALS " +
                "environment variable is not set or file does not exist.");
        }

        /// <summary>
        /// Estimates the in-memory size of a RecordBatch by summing the buffer lengths
        /// of each column's underlying Arrow arrays.
        /// </summary>
        private static long EstimateBatchBytes(RecordBatch batch)
        {
            long bytes = 0;
            for (int col = 0; col < batch.ColumnCount; col++)
            {
                IArrowArray array = batch.Column(col);
                bytes += EstimateArrayBytes(array);
            }
            return bytes;
        }

        private static long EstimateArrayBytes(IArrowArray array)
        {
            long bytes = 0;
            Apache.Arrow.ArrayData data = array.Data;
            if (data.Buffers != null)
            {
                foreach (ArrowBuffer buffer in data.Buffers)
                {
                    bytes += buffer.Length;
                }
            }
            if (data.Children != null)
            {
                foreach (ArrayData child in data.Children)
                {
                    if (child?.Buffers != null)
                    {
                        foreach (ArrowBuffer buffer in child.Buffers)
                        {
                            bytes += buffer.Length;
                        }
                    }
                }
            }
            return bytes;
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
