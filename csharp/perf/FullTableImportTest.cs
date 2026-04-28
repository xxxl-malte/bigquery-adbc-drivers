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
        /// Reads all rows from the configured BigQuery table using SELECT * and measures
        /// connection time, query execution time, data transfer time, and total time.
        /// </summary>
        [SkippableFact]
        public async Task MeasureFullTableImport()
        {
            foreach (PerfTestEnvironment env in _environments)
            {
                _output.WriteLine("==========================================================");
                _output.WriteLine($"Environment: {env.Name}");
                _output.WriteLine($"Table: {env.Catalog}.{env.Schema}.{env.Table}");
                _output.WriteLine("==========================================================");

                Stopwatch totalSw = Stopwatch.StartNew();

                // Phase 1: Connect
                Stopwatch connectSw = Stopwatch.StartNew();
                Dictionary<string, string> parameters = BuildParameters(env);
                AdbcDatabase database = new BigQueryDriver().Open(parameters);
                using AdbcConnection connection = database.Connect(new Dictionary<string, string>());
                connectSw.Stop();
                _output.WriteLine($"Connection time: {connectSw.Elapsed}");

                // Phase 2: Execute query
                Stopwatch querySw = Stopwatch.StartNew();
                using AdbcStatement statement = connection.CreateStatement();

                string fullyQualifiedTable = $"`{env.Catalog}`.`{env.Schema}`.`{env.Table}`";
                statement.SqlQuery = $"SELECT * FROM {fullyQualifiedTable}";
                _output.WriteLine($"Query: {statement.SqlQuery}");

                QueryResult queryResult = statement.ExecuteQuery();
                querySw.Stop();
                _output.WriteLine($"Query execution time: {querySw.Elapsed}");

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
                    _output.WriteLine($"Schema: {columnCount} columns");
                    foreach (Field field in schema.FieldsList)
                    {
                        _output.WriteLine($"  {field.Name}: {field.DataType.TypeId}");
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
                _output.WriteLine("");
                _output.WriteLine("--- Timing ---");
                _output.WriteLine($"  Connection:       {connectSw.Elapsed}");
                _output.WriteLine($"  Query execution:  {querySw.Elapsed}");
                _output.WriteLine($"  Time to 1st batch:{timeToFirstBatch}");
                _output.WriteLine($"  Data transfer:    {readSw.Elapsed}");
                _output.WriteLine($"  Total:            {totalSw.Elapsed}");

                _output.WriteLine("");
                _output.WriteLine("--- Volume ---");
                _output.WriteLine($"  Total rows:       {totalRows:N0}");
                _output.WriteLine($"  Total batches:    {totalBatches:N0}");
                _output.WriteLine($"  Columns:          {columnCount}");
                _output.WriteLine($"  Total bytes (est):{totalBytes:N0} ({FormatBytes(totalBytes)})");

                if (batchRowCounts.Count > 0)
                {
                    _output.WriteLine($"  Avg batch size:   {batchRowCounts.Average():N0} rows");
                    _output.WriteLine($"  Min batch size:   {batchRowCounts.Min():N0} rows");
                    _output.WriteLine($"  Max batch size:   {batchRowCounts.Max():N0} rows");
                }

                _output.WriteLine("");
                _output.WriteLine("--- Throughput ---");
                double readSeconds = readSw.Elapsed.TotalSeconds;
                double totalSeconds = totalSw.Elapsed.TotalSeconds;
                if (readSeconds > 0)
                {
                    _output.WriteLine($"  Rows/sec (read):  {totalRows / readSeconds:N0}");
                    _output.WriteLine($"  Bytes/sec (read): {totalBytes / readSeconds:N0} ({FormatBytes((long)(totalBytes / readSeconds))}/s)");
                }
                if (totalSeconds > 0)
                {
                    _output.WriteLine($"  Rows/sec (total): {totalRows / totalSeconds:N0}");
                    _output.WriteLine($"  Bytes/sec (total):{totalBytes / totalSeconds:N0} ({FormatBytes((long)(totalBytes / totalSeconds))}/s)");
                }

                _output.WriteLine("==========================================================");
                _output.WriteLine("");
            }
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
                int iterations = env.Iterations > 0 ? env.Iterations : 3;

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

        private static Dictionary<string, string> BuildParameters(PerfTestEnvironment env)
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
                    parameters["adbc.bigquery.auth_json_credential"] = env.JsonCredential ?? "";
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
