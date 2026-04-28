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

using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace AdbcDrivers.BigQuery.Perf
{
    /// <summary>
    /// Root configuration for performance tests.
    /// </summary>
    public class PerfTestConfiguration
    {
        [JsonPropertyName("environments")]
        public List<PerfTestEnvironment> Environments { get; set; } = new List<PerfTestEnvironment>();
    }

    /// <summary>
    /// A single performance test environment specifying connection details
    /// and the target table to benchmark.
    /// </summary>
    public class PerfTestEnvironment
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("projectId")]
        public string? ProjectId { get; set; }

        [JsonPropertyName("billingProjectId")]
        public string? BillingProjectId { get; set; }

        [JsonPropertyName("authenticationType")]
        public string? AuthenticationType { get; set; }

        [JsonPropertyName("jsonCredential")]
        public string? JsonCredential { get; set; }

        [JsonPropertyName("clientId")]
        public string? ClientId { get; set; }

        [JsonPropertyName("clientSecret")]
        public string? ClientSecret { get; set; }

        [JsonPropertyName("refreshToken")]
        public string? RefreshToken { get; set; }

        [JsonPropertyName("scopes")]
        public string? Scopes { get; set; }

        [JsonPropertyName("location")]
        public string? Location { get; set; }

        /// <summary>
        /// The BigQuery project (catalog) containing the target table.
        /// </summary>
        [JsonPropertyName("catalog")]
        public string Catalog { get; set; } = string.Empty;

        /// <summary>
        /// The BigQuery dataset (schema) containing the target table.
        /// </summary>
        [JsonPropertyName("schema")]
        public string Schema { get; set; } = string.Empty;

        /// <summary>
        /// The BigQuery table name to import.
        /// </summary>
        [JsonPropertyName("table")]
        public string Table { get; set; } = string.Empty;

        /// <summary>
        /// Number of parallel read streams (maps to adbc.bigquery.max_fetch_concurrency).
        /// </summary>
        [JsonPropertyName("maxStreamCount")]
        public int? MaxStreamCount { get; set; }

        /// <summary>
        /// Whether to enable large results support.
        /// </summary>
        [JsonPropertyName("allowLargeResults")]
        public bool AllowLargeResults { get; set; }

        /// <summary>
        /// Dataset for storing large results temp tables.
        /// </summary>
        [JsonPropertyName("largeResultsDataset")]
        public string? LargeResultsDataset { get; set; }

        /// <summary>
        /// Number of iterations for repeated tests. Defaults to 3 if not set.
        /// </summary>
        [JsonPropertyName("iterations")]
        public int Iterations { get; set; }
    }
}
