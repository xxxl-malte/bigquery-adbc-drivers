# Bugs Found in Performance Patch Series

This document catalogs bugs discovered during review of the 16 performance
patches in `csharp/patches/`. Each bug has been validated against the baseline
source code in `csharp/src/`.

---

## Bug 1 — Patch 03: `RetryTotalTimeoutMs` is never read from connection properties (dead code)

**File:** `BigQueryConnection.cs`
**Patch:** `03-retry-wallclock-timeout.patch`
**Severity:** Medium — the feature silently does nothing
**Status:** ✅ FIXED — parsing block added in `Open()` after `RetryDelayMs` block

### Description

The patch adds a `RetryTotalTimeoutMs` property with a default of `0` (disabled)
and a corresponding ADBC parameter constant `adbc.bigquery.retry_total_timeout_ms`.
The `RetryManager` implementation is correct — it creates a `Stopwatch`, checks
elapsed time before each attempt, and clamps inter-retry delays to the remaining
budget.

However, the `Open()` method — where **all** other retry parameters are parsed
from `this.properties` — is never updated to read `RetryTotalTimeoutMs`. The
existing parsing pattern in `Open()` (lines 108–126 of `BigQueryConnection.cs`)
handles `MaximumRetryAttempts` and `RetryDelayMs` but has no equivalent block for
`RetryTotalTimeoutMs`:

```csharp
// MaxRetryAttempts — parsed in Open() ✅  (line 108)
if (this.properties.TryGetValue(BigQueryParameters.MaximumRetryAttempts, out string? sRetryAttempts) &&
    int.TryParse(sRetryAttempts, out int retries) && retries >= 0)
{
    MaxRetryAttempts = retries;
}

// RetryDelayMs — parsed in Open() ✅  (line 118)
if (this.properties.TryGetValue(BigQueryParameters.RetryDelayMs, out string? sRetryDelay) &&
    int.TryParse(sRetryDelay, out int delay) && delay >= 0)
{
    RetryDelayMs = delay;
}

// RetryTotalTimeoutMs — NO parsing block exists anywhere in Open() ❌
internal int RetryTotalTimeoutMs { get; private set; } = 0;
```

Since the property has `private set` and defaults to `0`, the wall-clock timeout
is permanently disabled regardless of what the user configures via connection
properties. The entire `Stopwatch`-based timeout logic in `RetryManager`
(including the deadline check at top-of-loop and the delay clamping) is dead code.

### Proposed Fix

Add a parsing block in `Open()` after the existing `RetryDelayMs` block
(after line 126), following the identical pattern:

```csharp
if (this.properties.TryGetValue(BigQueryParameters.RetryTotalTimeoutMs, out string? sTotalTimeout) &&
    int.TryParse(sTotalTimeout, out int totalTimeout) && totalTimeout >= 0)
{
    RetryTotalTimeoutMs = totalTimeout;
}
else if (sTotalTimeout != null)
{
    throw new ArgumentException(
        $"The value '{sTotalTimeout}' for parameter '{BigQueryParameters.RetryTotalTimeoutMs}' is not a valid non-negative integer.");
}
```

---

## Bug 2 — Patch 05: Old `BigQueryClient` leaked on every credential refresh

**File:** `BigQueryConnection.cs`
**Patch:** `05-skip-credential-recreation.patch`
**Severity:** High — resource leak accumulates over time
**Status:** ✅ FIXED — old client disposed before replacement in `RefreshClient()`

### Description

The patch introduces a new `RefreshClient()` method that creates a new
`BigQueryClient` and assigns it to `Client`, but never disposes the previous
instance:

```csharp
private void RefreshClient()
{
    this.TraceActivity(activity =>
    {
        SetCredential();
        // ...
        BigQueryClient client = builder.Build();

        if (ClientTimeout.HasValue)
            client.Service.HttpClient.Timeout = ClientTimeout.Value;

        Client = client;  // ← old Client is silently orphaned
    }, ClassName + "." + nameof(RefreshClient));
}
```

`BigQueryClient` wraps a Google API service object with an `HttpClient`
(confirmed at line 405 of the baseline: `client.Service.HttpClient.Timeout`).
Each `RefreshClient()` call leaks the previous client's HTTP connections and
socket handles.

Note: the baseline `UpdateClientToken()` → `Open()` path (line 690 → 408) has
the same leak pattern (`Client = client` without disposing the old). However,
this patch introduces a brand-new code path specifically designed for repeated
credential refreshes, making the leak more impactful — `RefreshClient()` is
called on every token refresh, which can happen frequently for short-lived
credentials.

### Proposed Fix

Capture and dispose the old client before replacement:

```csharp
BigQueryClient client = builder.Build();

if (ClientTimeout.HasValue)
    client.Service.HttpClient.Timeout = ClientTimeout.Value;

var oldClient = Client;
Client = client;
oldClient?.Dispose();
```

---

## Bug 3 — Patch 06: Old gRPC channel leaked on credential rebuild

**File:** `TokenProtectedReadClient.cs`
**Patch:** `06-reuse-grpc-channel.patch`
**Severity:** High — gRPC channel (TCP + TLS + HTTP/2) leaked on each rebuild
**Status:** ✅ FIXED — old client captured and `ShutdownChannelAsync()` called in `UpdateCredential()`

### Description

When `UpdateCredential` is called with a genuinely new credential object, a new
`BigQueryReadClient` is built but the old one is never disposed:

```csharp
lock (_rebuildLock)
{
    if (ReferenceEquals(credential, _lastCredential) && bigQueryReadClient != null)
        return;  // skip if same credential — good

    BigQueryReadClientBuilder readClientBuilder = new BigQueryReadClientBuilder();
    readClientBuilder.Credential = credential;
    this.bigQueryReadClient = readClientBuilder.Build();  // ← old client orphaned
    _lastCredential = credential;
}
```

Each `BigQueryReadClient` owns a `GrpcChannel` (TCP connection, TLS session,
HTTP/2 multiplexer). The patch commit message acknowledges keeping the old
client alive to "prevent NPE races during streaming reads," but provides no
mechanism to ever clean it up — not even after in-flight reads complete.

In the baseline, a new `TokenProtectedReadClientManger` is created per query
(line 195 of `BigQueryStatement.cs`), so the leak only occurs on token refresh
within a single query. After patch 11 moves the client to connection level, the
same instance is reused across all queries, making credential-rebuild leaks
accumulate for the entire connection lifetime.

### Proposed Fix

Track the old client and schedule deferred disposal. Since in-flight reads may
hold a reference, use a delayed cleanup approach:

```csharp
lock (_rebuildLock)
{
    if (ReferenceEquals(credential, _lastCredential) && bigQueryReadClient != null)
        return;

    var oldClient = this.bigQueryReadClient;

    BigQueryReadClientBuilder readClientBuilder = new BigQueryReadClientBuilder();
    readClientBuilder.Credential = credential;
    this.bigQueryReadClient = readClientBuilder.Build();
    _lastCredential = credential;

    // ShutdownAsync is the gRPC-recommended way to drain and close a channel.
    // Fire-and-forget is acceptable — the old channel will finish in-flight RPCs
    // and then release resources.
    if (oldClient != null)
    {
        _ = oldClient.ShutdownChannelAsync();
    }
}
```

If `BigQueryReadClient` does not expose `ShutdownChannelAsync`, an alternative is
to extract the underlying `GrpcChannel` from the client's `ServiceMetadata` and
call `channel.ShutdownAsync()`, or to maintain a list of retired clients and
dispose them in the owning connection's `Dispose()`.

---

## Bug 4 — Patch 08: `Parallel.ForEach` causes thread pool starvation

**File:** `BigQueryConnection.cs`
**Patch:** `08-parallel-getobjects.patch`
**Severity:** High — can deadlock under load
**Status:** ✅ FIXED — full async chain with `Task.WhenAll` replaces `Parallel.ForEach`

### Description

The patch uses `Parallel.ForEach` to parallelize `GetDbSchemas` calls across
matching project IDs:

```csharp
var schemaResults = new ConcurrentDictionary<string, StructArray>();
System.Threading.Tasks.Parallel.ForEach(matchingProjectIds, projectId =>
{
    schemaResults[projectId] = GetDbSchemas(
        depth, projectId, dbSchemaPattern,
        tableNamePattern, tableTypes, columnNamePattern);
});
```

`GetDbSchemas` internally performs sync-over-async at line 833 of the baseline:

```csharp
PagedEnumerable<DatasetList, BigQueryDataset>? schemas =
    ExecuteWithRetriesAsync<...>(func, activity).GetAwaiter().GetResult();
```

`Parallel.ForEach` schedules iterations on thread pool threads. Each iteration
blocks a thread pool thread via `.GetAwaiter().GetResult()`, waiting for an async
I/O operation (BigQuery API call) to complete. The async continuations from those
operations also need thread pool threads to run. With enough matching project IDs,
all available thread pool threads are blocked waiting for continuations that can
never be scheduled — a classic thread pool starvation deadlock.

The problem compounds because `GetDbSchemas` → `GetTableSchemas` → `GetColumnSchema`
chains additional sync-over-async calls, each consuming more thread pool threads.

### Proposed Fix

Replace `Parallel.ForEach` with `Task.WhenAll` using async versions of the
methods. This requires making `GetDbSchemas` (and its callees) properly async:

```csharp
// Option A: If methods can be made async
var tasks = matchingProjectIds.Select(async projectId =>
{
    var result = await GetDbSchemasAsync(
        depth, projectId, dbSchemaPattern,
        tableNamePattern, tableTypes, columnNamePattern);
    return (projectId, result);
});
var results = await Task.WhenAll(tasks);
foreach (var (projectId, schema) in results)
{
    catalogNameBuilder.Append(projectId);
    catalogDbSchemasValues.Add(schema);
}
```

If making the full chain async is too invasive, a minimal fix is to constrain
`Parallel.ForEach` with `MaxDegreeOfParallelism` to prevent exhausting the pool:

```csharp
// Option B: Limit parallelism (mitigation, not full fix)
Parallel.ForEach(matchingProjectIds,
    new ParallelOptions { MaxDegreeOfParallelism = Math.Min(4, Environment.ProcessorCount) },
    projectId => { ... });
```

Option B reduces the starvation risk but doesn't eliminate it — the sync-over-async
pattern remains fundamentally hazardous.

---

## Bug 5 — Patch 08: `Parallel.ForEach` wraps exceptions in `AggregateException`

**File:** `BigQueryConnection.cs`
**Patch:** `08-parallel-getobjects.patch`
**Severity:** Medium — breaks exception handling for callers
**Status:** ✅ FIXED — auto-fixed by async chain (`await` unwraps `AggregateException`)

### Description

The baseline sequential loop in `GetCatalogs` (line 779) calls `GetDbSchemas`
directly. Any exception (e.g., `GoogleApiException` for permission errors) is
thrown as-is and can be caught by type-specific `catch` blocks.

`Parallel.ForEach` catches all exceptions from its body delegates and wraps them
in an `AggregateException`. Callers that catch specific exception types will miss
the wrapped inner exceptions:

```csharp
// Caller code that works with sequential execution:
try { GetObjects(...); }
catch (GoogleApiException ex) { /* handle auth error */ }

// After patch 08, GoogleApiException is wrapped:
// throws AggregateException { InnerExceptions: [ GoogleApiException ] }
// The catch (GoogleApiException) block never fires.
```

The `RetryManager` (line 70 of baseline) checks
`tokenProtectedResource?.TokenRequiresUpdate(ex)` — this calls
`BigQueryUtils.TokenRequiresUpdate(ex)` which may not unwrap
`AggregateException` to find the inner `GoogleApiException`, breaking the
token-refresh retry path.

### Proposed Fix

Wrap the `Parallel.ForEach` call in a try/catch that unwraps single-exception
`AggregateException`s:

```csharp
try
{
    Parallel.ForEach(matchingProjectIds, projectId => { ... });
}
catch (AggregateException ae) when (ae.InnerExceptions.Count == 1)
{
    System.Runtime.ExceptionServices.ExceptionDispatchInfo
        .Capture(ae.InnerExceptions[0]).Throw();
}
```

For multi-exception scenarios (multiple projects failing), decide on a policy —
throw the first, aggregate into a single `AdbcException`, etc.

---

## Bug 6 — Patch 09: Batched data is fetched but never used (N+1 queries remain)

**File:** `BigQueryConnection.cs`
**Patch:** `09-batch-information-schema.patch`
**Severity:** High — makes performance strictly worse
**Status:** ✅ FIXED — pre-fetched rows wired into `GetColumnSchemaAsync`/`GetConstraintSchemaAsync` via optional parameter

### Description

The patch adds two new methods — `BatchFetchColumns()` and
`BatchFetchConstraints()` — that execute dataset-wide INFORMATION_SCHEMA queries
and group results into dictionaries keyed by table name. The patch description
states: *"The pre-fetched data is passed to the existing builder methods."*

However, the dictionaries are computed and then **never referenced again**. The
original per-table methods are still called unchanged:

```csharp
// Batch queries execute here (lines added by the patch):
Dictionary<string, List<BigQueryRow>>? batchedColumns =
    (depth != GetObjectsDepth.Tables) ? BatchFetchColumns(catalog, dbSchema, columnNamePattern) : null;
Dictionary<string, List<BigQueryRow>>? batchedConstraints =
    (depth == GetObjectsDepth.All && includeConstraints) ? BatchFetchConstraints(catalog, dbSchema) : null;

// But inside the per-table loop, the ORIGINAL N+1 methods are still called:
foreach (BigQueryRow row in result)
{
    // ...
    tableColumnsValues.Add(GetColumnSchema(catalog, dbSchema, tableName, columnNamePattern));          // ← per-table query
    tableConstraintsValues.Add(GetConstraintSchema(depth, catalog, dbSchema, tableName, columnNamePattern)); // ← per-table query
}
```

`GetColumnSchema` (line 968) and `GetConstraintSchema` (line 1084) have not
been modified to accept pre-fetched data. Both still construct and execute their
own SQL queries internally. The `batchedColumns` and `batchedConstraints`
variables are unused local variables.

**Net effect:** For a dataset with N tables, the query count goes from N+1
(1 TABLES query + N COLUMNS queries) to N+3 (1 TABLES + 1 batch COLUMNS +
N individual COLUMNS + 1 batch CONSTRAINTS). The batch queries are pure overhead.

### Proposed Fix

Two options:

**Option A (Complete the wiring):** Modify `GetColumnSchema` and
`GetConstraintSchema` to accept an optional pre-fetched row list, bypassing the
SQL query when provided:

```csharp
// Add overload or optional parameter:
private StructArray GetColumnSchema(
    string catalog, string dbSchema, string table,
    string? columnNamePattern,
    List<BigQueryRow>? prefetchedRows = null)  // ← new parameter
{
    // ...
    List<BigQueryRow> rows;
    if (prefetchedRows != null)
    {
        rows = prefetchedRows;  // use pre-fetched data
    }
    else
    {
        BigQueryResults? result = ExecuteQuery(query, parameters: null);
        rows = result?.ToList() ?? new List<BigQueryRow>();
    }
    // ... rest of builder logic unchanged
}

// In the loop:
batchedColumns?.TryGetValue(tableName, out var prefetchedCols);
tableColumnsValues.Add(GetColumnSchema(catalog, dbSchema, tableName, columnNamePattern, prefetchedCols));
```

**Option B (Remove dead code):** If the wiring work is not ready, remove the
`BatchFetchColumns`/`BatchFetchConstraints` calls entirely to avoid the overhead.

---

## Bug 7 — Patch 11: Race condition in `UpdateToken` lambda after `Dispose()`

**File:** `BigQueryConnection.cs`
**Patch:** `11-cache-grpc-channel-per-connection.patch`
**Severity:** Medium — `NullReferenceException` on concurrent dispose + token refresh
**Status:** ✅ FIXED — lambda captures local `mgr` variable instead of `ReadClientManager` property

### Description

The patch moves `TokenProtectedReadClientManger` from per-query creation
(line 195 of baseline `BigQueryStatement.cs`) to a connection-level property.
The `UpdateToken` lambda captures `ReadClientManager` through the property
accessor, not a local variable:

```csharp
// In Open(), after creating the shared ReadClientManager:
ReadClientManager = new TokenProtectedReadClientManger(Credential!);
ReadClientManager.UpdateToken = () => Task.Run(() =>
{
    SetCredential();
    ReadClientManager.UpdateCredential(Credential);
    //  ↑ reads the property each time — not a captured local
});
```

`Dispose()` nulls the property without synchronization:

```csharp
public override void Dispose()
{
    Client?.Dispose();
    Client = null;
    ReadClientManager = null;  // ← no coordination with in-flight token refresh
    this.httpClient?.Dispose();
    this._fileActivityListener?.Dispose();
}
```

If a token refresh fires concurrently with `Dispose()` (e.g., a streaming read
triggers a token refresh while the application is shutting down), the lambda
reads `ReadClientManager` after it has been set to `null`, causing a
`NullReferenceException` inside `Task.Run`.

Additionally, `Dispose()` only nulls the reference and relies on the GC finalizer
to clean up the underlying gRPC channel. The `BigQueryReadClient` wraps a
`GrpcChannel` (TCP+TLS+HTTP/2 resources), and finalizer-based cleanup for
network resources is unreliable — the finalizer may run late, or never under
memory pressure.

### Proposed Fix

Capture the `ReadClientManager` in a local variable within the lambda, and
add a null-check:

```csharp
var mgr = new TokenProtectedReadClientManger(Credential!);
ReadClientManager = mgr;
mgr.UpdateToken = () => Task.Run(() =>
{
    var currentMgr = ReadClientManager;
    if (currentMgr == null) return;  // connection disposed, skip refresh
    SetCredential();
    currentMgr.UpdateCredential(Credential);
});
```

For proper resource cleanup in `Dispose()`, attempt to shut down the gRPC
channel. If `BigQueryReadClient` doesn't expose `Dispose()` directly, track the
underlying `GrpcChannel` separately:

```csharp
public override void Dispose()
{
    Client?.Dispose();
    Client = null;

    var mgr = ReadClientManager;
    ReadClientManager = null;
    // If a ShutdownAsync or similar API is available:
    // mgr?.ShutdownAsync().GetAwaiter().GetResult();

    this.httpClient?.Dispose();
    this._fileActivityListener?.Dispose();
}
```

---

## Bug 8 — Patch 15: Non-thread-safe `disposed` flag enables double-dispose race

**File:** `BigQueryStatement.cs` (inner class `ReadRowsStream`)
**Patch:** `15-async-dispose-readrowsstream.patch`
**Severity:** Medium — double-dispose of gRPC response stream
**Status:** ✅ FIXED — `Interlocked.Exchange` for thread-safe disposed guard; `MultiArrowReader` implements `IAsyncDisposable`

### Description

The patch adds `IAsyncDisposable` to `ReadRowsStream` with the following
implementation:

```csharp
public async ValueTask DisposeAsync()
{
    if (!this.disposed)           // Thread A reads false
    {                              // Thread B also reads false (no barrier)
        if (this.response != null)
        {
            await this.response.DisposeAsync().ConfigureAwait(false);
            //  ↑ both threads enter here — double-dispose of gRPC stream enumerator
        }
        this.disposed = true;
    }
}
```

The `disposed` field is a plain `bool` (declared at line 1459 of the baseline).
There is no `volatile`, `Interlocked`, or lock protection. The race window is
especially wide because of the `await` between the check and the flag set — a
second caller can enter and pass the check while the first is awaiting
`DisposeAsync`.

The baseline `Dispose()` (line 1658) has the same non-thread-safe pattern, but
the sync version has a narrower race window (no await between check and set). The
patch introduces `async` disposal which **widens** the race window while failing
to fix the underlying thread-safety issue.

Additionally, `MultiArrowReader.Dispose` (the primary caller at line 1421 in the
baseline) is updated to prefer `DisposeAsync`, but still blocks synchronously:

```csharp
if (reader is IAsyncDisposable ad)
{
    ad.DisposeAsync().AsTask().GetAwaiter().GetResult();  // still sync-over-async
}
```

This contradicts the patch's stated goal of eliminating sync-over-async patterns.
The benefit only materializes if a future caller uses `await DisposeAsync()`
directly, but no such caller is introduced.

### Proposed Fix

Use `Interlocked` for the disposed guard, and add `DisposeAsync` to
`MultiArrowReader`:

```csharp
// In ReadRowsStream:
private int _disposed = 0;  // replaces bool disposed

public async ValueTask DisposeAsync()
{
    if (Interlocked.Exchange(ref _disposed, 1) == 0)
    {
        if (this.response != null)
        {
            await this.response.DisposeAsync().ConfigureAwait(false);
        }
    }
}

public void Dispose()
{
    if (Interlocked.Exchange(ref _disposed, 1) == 0)
    {
        this.response?.DisposeAsync().AsTask().GetAwaiter().GetResult();
    }
}
```

To actually eliminate the sync-over-async in `MultiArrowReader`, make it
implement `IAsyncDisposable` too:

```csharp
// In MultiArrowReader:
protected override async ValueTask DisposeAsyncCore()
{
    if (!this.disposed)
    {
        // ...
        foreach (var reader in this.readerList)
        {
            if (reader is IAsyncDisposable ad)
                await ad.DisposeAsync();
            else if (reader is IDisposable d)
                d.Dispose();
        }
        // ...
        this.disposed = true;
    }
}
```

---

## Bug 9 — Patch 10: `GC.Collect` between batches does not reduce peak memory

**File:** `BigQueryConnection.cs`
**Patch:** `10-reduce-metadata-memory.patch`
**Severity:** Low — ineffective optimization, not a correctness bug
**Status:** ✅ FIXED — `ChunkedGetObjectsStream` yields one `RecordBatch` per catalog for true streaming memory reduction

### Description

The patch splits schema processing into configurable-size batches (default 50)
and calls `GC.Collect(0, GCCollectionMode.Optimized, false)` between batches:

```csharp
for (int batchStart = 0; batchStart < matchingSchemas.Count; batchStart += metadataBatchSize)
{
    int batchEnd = Math.Min(batchStart + metadataBatchSize, matchingSchemas.Count);

    for (int i = batchStart; i < batchEnd; i++)
    {
        string schemaId = matchingSchemas[i];
        dbSchemaNameBuilder.Append(schemaId);          // ← grows across all batches
        // ...
        dbSchemaTablesValues.Add(GetTableSchemas(...)); // ← grows across all batches
    }

    if (batchEnd < matchingSchemas.Count)
    {
        GC.Collect(0, GCCollectionMode.Optimized, false);  // ← what can this collect?
    }
}
```

The `dbSchemaNameBuilder`, `dbSchemaTablesValues`, `nullBitmapBuffer`, etc. are
declared **outside** the batch loop and accumulate data monotonically across all
batches. The `GC.Collect` call can only reclaim short-lived temporaries
(iterator state, temporary strings) — the actual Arrow builder contents and
`StructArray` results remain alive and growing.

The explicit `GC.Collect` call is also an anti-pattern in .NET:
- `GCCollectionMode.Optimized` allows the runtime to ignore the hint entirely
- Even when honored, it promotes surviving gen-0 objects to gen-1 prematurely,
  increasing mid-life-crisis GC pressure
- The runtime's own heuristics would trigger gen-0 collections at appropriate
  times without explicit calls

### Proposed Fix

For a true memory reduction, the method would need to emit intermediate
`RecordBatch`es between batches, disposing each before starting the next.
This requires changing the return type from a single `StructArray` to an
`IArrowArrayStream` that yields multiple batches — an architectural change to
the ADBC interface contract.

As a pragmatic improvement, simply remove the `GC.Collect` call and the batching
structure (since it adds complexity without benefit), or if batching is preserved
for future streaming support, at minimum remove the `GC.Collect`:

```csharp
// Remove this — it does nothing useful and may hurt performance:
// GC.Collect(0, GCCollectionMode.Optimized, false);
```

---

## Summary

| # | Patch | Bug | Severity | Status |
|---|-------|-----|----------|--------|
| 1 | 03 — Retry timeout | Timeout property never parsed from config; feature is dead code | Medium | ✅ FIXED |
| 2 | 05 — Skip credential recreation | Old `BigQueryClient`/`HttpClient` leaked on every refresh | High | ✅ FIXED |
| 3 | 06 — Reuse gRPC channel | Old `BigQueryReadClient` gRPC channels leaked on rebuild | High | ✅ FIXED |
| 4 | 08 — Parallel GetObjects | Sync-over-async inside `Parallel.ForEach` → thread pool starvation | High | ✅ FIXED |
| 5 | 08 — Parallel GetObjects | `AggregateException` wrapping changes error semantics | Medium | ✅ FIXED |
| 6 | 09 — Batch INFORMATION_SCHEMA | Batch data fetched but never used; adds overhead to existing N+1 | High | ✅ FIXED |
| 7 | 11 — Cache gRPC channel | Race condition: `UpdateToken` lambda NPE after `Dispose()` | Medium | ✅ FIXED |
| 8 | 15 — Async dispose ReadRowsStream | Non-thread-safe `disposed` check; sync-over-async not actually fixed | Medium | ✅ FIXED |
| 9 | 10 — Reduce metadata memory | `GC.Collect` ineffective; peak memory unchanged | Low | ✅ FIXED |

### Patches with no bugs found

| Patch | Verdict |
|-------|---------|
| 01 — Fix PatternToRegEx | ✅ Correct — `Regex.Escape()` does not escape `_` or `%` (not regex metacharacters), so the subsequent `.Replace("_", ".").Replace("%", ".*")` works correctly on the escaped string |
| 02 — Parameterized metadata queries | ✅ Correct — proper use of `BigQueryParameter` for WHERE clause values; FROM-clause identifiers correctly remain as `Sanitize()`-quoted interpolation (BigQuery does not support parameterized identifiers) |
| 04 — Persist detected project ID | ✅ Correct — `PersistProperty` writes to `Dictionary<string,string>` without locking, which is technically not thread-safe for concurrent readers, but the write happens once during first query execution and the practical risk is negligible |
| 07 — Async-first ExecuteQuery | ✅ Correct — `override` keyword validates signature match with base class; try/catch structure mirrors the sync versions exactly |
| 12 — Parallel GetJob multi-statement | ✅ Correct — transforms sequential `.Select(job => Client.GetJob(...))` to `Task.WhenAll(Client.GetJobAsync(...))` with proper async/await; child job count is bounded by statement count |
| 13 — Fix Sanitize regex anchor | ✅ Correct — adds `$` end-anchor to `sanitizedInputRegex`, preventing inputs like `"abc;DROP TABLE x"` from passing validation on the valid prefix alone. This is an important security fix. |
| 14 — Fix HttpClient leak | ✅ Correct — replaces `new HttpClient()` inside `GetAccessToken` (line 1576 of baseline) with the class-level `this.httpClient` field; `HttpClient.SendAsync` is thread-safe |
| 16 — Enable Arrow LZ4 compression | ✅ Correct — sets `ArrowSerializationOptions.BufferCompression = LZ4_FRAME` in `CreateReadSession`; LZ4 decompression is handled transparently by the Arrow IPC library |
