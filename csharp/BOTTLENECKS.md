# C# Driver — Performance Bottlenecks

A thorough analysis of the C# BigQuery ADBC driver implementation.

---

### 1. N+1 INFORMATION_SCHEMA queries in `GetObjects` (`BigQueryConnection.cs:874-966, 968-1082, 1084-1238`)

`GetTableSchemas` runs one `INFORMATION_SCHEMA.TABLES` query per dataset, then for **each
table** issues a separate `INFORMATION_SCHEMA.COLUMNS` query and, if constraints are
requested, additional `TABLE_CONSTRAINTS`, `KEY_COLUMN_USAGE`, and
`CONSTRAINT_COLUMN_USAGE` queries. For a dataset with 100 tables this can mean 300+
individual BigQuery jobs.

**Impact:** `GetObjects` at full depth is extremely slow on datasets with many tables.

### 2. Synchronous-over-async throughout the driver (`BigQueryStatement.cs:133-143, 751-761`)

Public methods like `ExecuteQuery()` and `ExecuteUpdate()` call
`.GetAwaiter().GetResult()` on their async implementations. This blocks a thread-pool
thread on every async I/O hop, reducing effective concurrency and risking thread-pool
starvation under load.

**Impact:** Thread pool pressure; potential deadlocks in UI/ASP.NET contexts.

### 3. `ValidateOptions` re-detects project ID after every token refresh (`BigQueryStatement.cs:914-944`, `BigQueryConnection.cs:304-411, 687-691`)

When `Client.ProjectId` equals the sentinel `DetectProjectId`, `ValidateOptions` calls
`ListProjects()` (wrapped in retries) and then **re-opens the client** via
`bigQueryConnection.Open(firstProjectId)`. This correctly sets `Client.ProjectId` (line
408), so subsequent calls skip the block — **until a token refresh occurs**.

`UpdateClientToken()` calls `Open()` with no arguments, which falls back to
`DetectProjectId` (line 316) because the detected project ID is never persisted into
`this.properties`. This resets `Client.ProjectId` to `DetectProjectId`, causing the next
statement execution to re-detect via `ListProjects` + full client reconstruction.

**Impact:** Redundant `ListProjects` API call + client reconstruction after every token
refresh cycle when using project auto-detection.

### 4. `UpdateClientToken` re-creates the entire `BigQueryClient` (`BigQueryConnection.cs:687-691, 304-411`)

On token refresh, the driver discards the old `BigQueryClient` and calls `Open()` to
build a new one (line 690). `Open()` re-runs the full credential setup (`SetCredential`,
line 373), constructs a new `BigQueryClientBuilder` (line 375), and builds a fresh
`BigQueryClient` (line 401). The comment on line 689 acknowledges this is an SDK
limitation: *"there isn't a way to set the credentials, just need to open a new client"*.

**Impact:** Heavy object churn on every token refresh cycle, including credential
re-parsing and HTTP client reconstruction.

### 5. `TokenProtectedReadClientManger` rebuilds the gRPC client on credential update (`TokenProtectedReadClient.cs:50-59`)

`UpdateCredential` constructs a new `BigQueryReadClient` (a gRPC channel) from scratch
rather than refreshing the token source on an existing channel. During long-running reads
this can cause unnecessary reconnections.

**Impact:** gRPC channel teardown/rebuild during active streaming reads.

### 6. No parallelism in `GetCatalogs` → `GetDbSchemas` → `GetTableSchemas` chain (`BigQueryConnection.cs:745-966`)

The `GetObjects` hierarchy processes each catalog, then each dataset, then each table
strictly sequentially. Independent datasets (or tables) could be fetched in parallel.

**Impact:** Wall-clock time scales linearly with the number of datasets × tables.

### 7. `PatternToRegEx` does not escape regex metacharacters (`BigQueryConnection.cs:1240-1251`)

`_` is replaced with `.` and `%` with `.*`, but other regex-special characters in the
input (e.g., `(`, `[`, `+`) are not escaped. Besides correctness, this means the regex
engine may backtrack on adversarial patterns.

**Impact:** Potential catastrophic regex backtracking; incorrect filtering results.

### 8. `string.Format` with `Sanitize` for SQL construction (`BigQueryConnection.cs:891-909, 998-1003`)

Metadata queries are built via string formatting rather than parameterized queries. While
`Sanitize` provides some protection, using `BigQueryParameter` (as done in the Go driver's
statistics queries) would be safer and would let BigQuery cache query plans.

**Impact:** Missed query-plan caching; wider attack surface for injection.

---

## Cross-cutting (shared with Go driver)

### 9. No result-set streaming for metadata operations

Both drivers materialize the full metadata result into Arrow arrays in memory before
returning. For very large catalogs (thousands of tables, tens of thousands of columns)
this can cause significant memory spikes.

### 10. Retry budget is per-attempt, not per-operation

The `RetryManager` (default: 5 retries → 6 total attempts, 200ms initial delay, doubling
up to 5000ms cap) bounds retries by attempt count but not by total wall-clock time. Worst
case delay: 200 + 400 + 800 + 1600 + 3200 = 6200ms of sleep, plus the duration of 6
actual operation attempts. A sequence of slow transient errors can stall an operation
without the caller being able to bound the total wait.
