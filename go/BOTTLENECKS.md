# Go Driver — Performance Bottlenecks

A thorough analysis of the Go BigQuery ADBC driver implementation.

---

### 1. Sequential parameterized query execution (`record_reader.go:285-300`)

When bound parameters span multiple record batches, `newRecordReader` executes each
parameter row **sequentially** within `queryRecordWithSchemaCallback`. Each row triggers
a full BigQuery job (`runQuery`), waits for it to finish, and only then moves to the next
row. The `errgroup` concurrency limit (`prefetchConcurrency`) only gates the goroutines
that *read* IPC records into the channel — the queries themselves are serial.

**Impact:** Parameterized `SELECT` with N rows of bindings incurs N sequential round-trips.

### 2. `newRecordReader` blocks on `group.Wait()` before returning (`record_reader.go:298-300`)

After dispatching all queries, the function calls `group.Wait()` and then `close(ch)` —
all **before** returning the reader to the caller. This means the caller cannot begin
consuming results until every query has finished and every IPC record has been read into
memory. The channel buffer (`resultRecordBufferSize`) fills up and back-pressures, but
the fundamental problem is that reading is not pipelined with the caller's consumption.

Contrast this with `runPlainQuery`, which correctly streams in a background goroutine.

**Impact:** High latency and high memory for multi-parameter queries; the entire result
set is buffered before the caller sees any data.

### 3. Per-table metadata fetch in `GetTablesForDBSchema` (`connection.go:147-264`)

For every table that matches the filter, the code calls `table.Metadata(ctx)` individually.
This is an N+1 query pattern: one `Tables.List` call followed by one `Tables.Get` per
matching table. With hundreds of tables in a dataset this becomes very slow.

**Impact:** `GetObjects` at column depth is O(n) API calls per dataset.

### 4. `emptyArrowIterator.SerializedArrowSchema` allocates on every call (`record_reader.go:368-380`)

`SerializedArrowSchema()` creates a new `arrow.Schema`, serializes it via IPC, and returns
the bytes — every time it is called. The result is deterministic and could be computed once.
Additionally, failure calls `log.Fatalf`, crashing the process.

**Impact:** Minor per-call allocation waste; potential crash on error.

### 5. Disk I/O in bulk ingest "load" path (`bulk_ingest.go`)

The Parquet-based ingest writes each chunk to a local temporary file, closes it, re-opens
it for reading, and then uploads. This double-open (create → close → open for read) adds
unnecessary file-system round-trips and prevents streaming the data directly.

**Impact:** Extra I/O latency proportional to the number of ingested chunks.

### 6. Schema re-serialized per `Copy` call in Storage Write API path (`bulk_ingest_storage_write.go:285-291`)

Every call to `Copy` calls `serializeArrowSchema`, even though the schema does not change
between batches. The serialized bytes could be computed once in `Init` and reused.

**Impact:** Redundant CPU + allocation per batch during bulk ingest.

### 7. Single-stream ingest in Storage Write API (`bulk_ingest_storage_write.go`)

Only one `AppendRows` stream is used for the entire ingest. The BigQuery Storage Write API
supports multiple parallel streams, which would increase throughput for large ingestions.

**Impact:** Ingest throughput is limited to one gRPC stream.

### 8. `getTableStatistics` two sequential INFORMATION_SCHEMA queries (`connection_statistics.go:195-368`)

`getTableStatisticsBatch` runs a `PARTITIONS` query and, sequentially, a `TABLE_STORAGE`
query. These are independent and could be issued concurrently (e.g., using an `errgroup`).

**Impact:** Statistics retrieval takes the sum of both query durations instead of the max.

### 9. No connection pooling or client reuse across connections (`bigquery_database.go:66-102`)

Each `Database.Open` creates a brand-new `bigquery.Client` (and its underlying HTTP +
gRPC transport). The `bigquery.Client` is safe for concurrent use, but the driver never
shares it. For workloads that open many short-lived connections this wastes setup time.

**Impact:** Repeated TLS handshakes and client initialization overhead.

### 10. `getAccessToken` creates a new `http.Client` + `http.Transport` per call (`connection.go:1140-1198`)

When user OAuth is used, every token refresh allocates a fresh `http.Transport` and
`http.Client`. These are not pooled or reused, preventing TCP/TLS connection reuse.

**Impact:** Extra TLS handshake latency per token refresh.

---

## Cross-cutting (shared with C# driver)

### 11. No result-set streaming for metadata operations

Both drivers materialize the full metadata result into Arrow arrays in memory before
returning. For very large catalogs (thousands of tables, tens of thousands of columns)
this can cause significant memory spikes.

### 12. Retry budget is per-attempt, not per-operation

Both drivers implement retry loops (Go: `retryWithBackoff` with 20 attempts × 15 s max
backoff; C#: `RetryManager` with 5 retries × 5 s cap). Neither imposes a total wall-clock
deadline on the retry sequence. A sequence of slow transient errors can stall an operation
for minutes without the caller being able to bound the total wait.
