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

---

## Additional bottlenecks

### 11. New `TokenProtectedReadClientManger` (gRPC channel) per query (`BigQueryStatement.cs:195`)

Every call to `ExecuteQueryInternalAsync` constructs a new `TokenProtectedReadClientManger`
(line 195), whose constructor immediately builds a new `BigQueryReadClient` via
`BigQueryReadClientBuilder.Build()` (Google.Cloud.BigQuery.Storage.V1 v3.17.0). This
creates a new `GrpcChannel` with its own HTTP/2 connection pool. The first RPC on the new
channel (`CreateReadSession` at line 732) then establishes a fresh TCP + TLS + HTTP/2
connection, typically costing 50–200 ms. The previous query's channel is never disposed —
it is abandoned for GC finalisation, leaking its connections.

This is distinct from existing bottleneck #5, which describes the gRPC client being
rebuilt during *credential update*. This bottleneck is about a **new** client being
created on **every query execution** regardless of credential state.

**Impact:** Per-query TCP+TLS+HTTP/2 establishment overhead instead of amortising one
channel across the connection lifetime. Directly measurable on the perf-test hot path when
running multiple queries on the same connection.

### 12. Multi-statement path issues N+1 synchronous `GetJob` calls (`BigQueryStatement.cs:229-234`)

When a SCRIPT-type multi-statement query is detected, `ListJobs` enumerates child jobs and
then `.Select(job => Client.GetJob(job.Reference))` fetches full job details (including
`Statistics.ScriptStatistics` and `Statistics.Query.StatementType` needed for the
subsequent `.Where` filters) for **every** child job sequentially. The entire LINQ chain
is materialised with `.ToList()`, producing N+1 sequential REST round-trips.

This only applies to multi-statement (SCRIPT) queries. For single-statement queries (the
common case) this code path is not hit.

**Impact:** Sequential latency proportional to the number of child statements; each
`GetJob` is a separate REST API round-trip. A 20-statement script would issue 20+
sequential REST calls. Limited to SCRIPT queries only.

### 16. Arrow data transfer uses no compression (`BigQueryStatement.cs:742`)

The `CreateReadSession` request builds a `ReadSession` with `DataFormat = DataFormat.Arrow`
but does not set `ArrowSerializationOptions.BufferCompression`. By default the BigQuery
Storage API sends Arrow record batches uncompressed over gRPC. For large table imports the
raw byte volume is the dominant cost on the network path.

Setting `BufferCompression = CompressionCodec.Lz4Frame` tells the server to LZ4-compress
Arrow buffers before sending. LZ4 frame compression typically achieves 2–4× reduction on
columnar data while decompressing at ≈4 GB/s on the client — the CPU cost is negligible
compared to the network savings.

**Impact:** Directly reduces bytes transferred during the data-read phase of
`MeasureFullTableImport`. Improvement is proportional to data compressibility and
inversely proportional to available network bandwidth (larger benefit on constrained
links).

---

## Bugs found during audit (not performance bottlenecks)

### 13. `Sanitize` regex is not end-anchored — allows trailing content through (`BigQueryConnection.cs:1541-1558`)

`sanitizedInputRegex` is `^[a-zA-Z0-9_-]+` without a `$` anchor. .NET's `Regex.IsMatch`
returns `true` as soon as *any* match is found; with `^` only, the pattern matches the
valid prefix and ignores trailing characters. For example, `"abc;DROP TABLE x"` passes
because `"abc"` satisfies the pattern at position 0.

The values are used in both backtick-quoted identifiers (e.g.,
`` `{Sanitize(catalog)}` ``) and in single-quoted LIKE patterns (e.g.,
`WHERE table_name LIKE '{Sanitize(pattern)}'`). The backtick quoting likely prevents
exploitation in the identifier positions, but the unquoted LIKE-pattern position could be
more exposed.

**Impact:** This is a **correctness/security bug**, not a performance bottleneck.

### 14. New `HttpClient` allocated in `GetAccessToken` (`BigQueryConnection.cs:1576`)

`GetAccessToken` creates a local `HttpClient` (line 1576) that shadows the class-level
`this.httpClient` field (line 86). The local instance is never disposed. This is the
well-known .NET `HttpClient` anti-pattern (socket leak, DNS staleness).

However, tracing the actual call chain shows this is **not a performance bottleneck**:
`GetAccessToken` is only called for "user" authentication type, from `SetCredential()`,
which runs during `Open()`. `BigQueryConnection.UpdateToken` — the delegate the
`RetryManager` uses for automatic token refresh — is **never assigned internally**; it must
be set by the external caller (the README only shows the Entra ID case). For "user" auth
without an externally-wired `UpdateToken`, there is no automatic refresh loop. The method
is therefore called **at most 1–2 times per connection lifetime** (once during initial
`Open()`, possibly once more if `ValidateOptions` triggers re-opening for project-ID
auto-detection).

**Impact:** Resource leak (undisposed `HttpClient`), but called too infrequently to cause
socket exhaustion. A code quality bug, not a throughput bottleneck.

### 15. `ReadRowsStream.Dispose` blocks on async gRPC stream disposal (`BigQueryStatement.cs:1658-1665`)

`ReadRowsStream.Dispose()` calls `this.response?.DisposeAsync().GetAwaiter().GetResult()`.
This is sync-over-async disposal. In `MultiArrowReader.Dispose` (line 1419-1423), the
cancellation token is signalled first (`linkedCts.Cancel()`), then `producerTask` is
awaited, then each `ReadRowsStream` is disposed serially.

Because cancellation precedes disposal and the gRPC enumerator's `DisposeAsync` typically
completes quickly once the stream is cancelled, the blocking is usually brief. This is a
code quality issue (should implement `IAsyncDisposable`) but does not affect data-read
throughput — it runs only during post-read cleanup.

**Impact:** Sync-over-async code quality issue on the cleanup path, not a throughput
bottleneck.

---

## Investigated but **not** real bottlenecks

The following items were investigated during the audit but turned out to be non-issues:

**`Regex.IsMatch` in GetObjects loops (`BigQueryConnection.cs:781, 839`):** The static
`Regex.IsMatch(input, pattern, options)` method uses .NET's built-in regex cache (default
15 entries). The pattern is **not** re-compiled on every call — the cache handles it.
Combined with the small number of projects/datasets (typically single-digit to low
hundreds), the cost is negligible compared to the network calls made per project/dataset.

**`GC.GetTotalMemory(false)` per batch (`BigQueryStatement.cs:1395`):** Guarded by
`if (activity != null)`. When no tracing listener is registered,
`ActivitySource.StartActivity` returns `null`, so this code never runs. When tracing *is*
active, `GC.GetTotalMemory(false)` is a cheap counter read (no GC triggered, no heap
walk) — negligible relative to gRPC I/O per batch.

**Activity creation per batch (`BigQueryStatement.cs:1376, 1512`):** Each
`TraceActivityAsync` call invokes `ActivitySource.StartActivity`, which returns `null`
immediately when no listener is registered — no `Activity` object is allocated. The
remaining overhead is the delegate invocation and async state machine, which is modest
(a few hundred nanoseconds per batch). When tracing *is* active, per-batch Activities are
the expected instrumentation pattern.

**`ValidLocations` linear scan (`BigQueryConnection.cs:130`):** O(n) scan of ~45 entries,
called once per connection open. Connection open already involves credential setup, HTTP
client construction, and potentially network calls. The ~45 string comparisons are orders
of magnitude cheaper than anything else in `Open()`.

**`ValidateOptions` re-parsing per execution (`BigQueryStatement.cs:914-1021`):** Iterates
a small dictionary (~10 entries) and parses a few strings. Utterly negligible compared to
the BigQuery API call that follows. The project-ID re-detection issue within
`ValidateOptions` is already covered by existing bottleneck #3.

**Sync-over-async in token exchange (`BigQueryConnection.cs:1581-1582, 1612-1615`):**
These are specific instances of the general pattern already documented in bottleneck #2.
`GetAccessToken` and `TradeEntraIdTokenForBigQueryToken` are called from `SetCredential`,
which is invoked within the synchronous `Open()` call chain. The entire chain would need to
be made async, which is the same fix as bottleneck #2.
