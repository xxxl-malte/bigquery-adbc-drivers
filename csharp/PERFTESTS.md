# Performance Test Results

**Commit:** `6c26e15b5411c4954f29535f3f03c6dbbcdb9c00`
**Suite started:** 2026-04-29 13:55:00 UTC
**Last updated:** 2026-04-29 14:28:20 UTC
**Patches:** 16 applied incrementally

## Summary

| # | Configuration | Status | Completed | Total Rows | Total Batches | Total Time | Throughput (rows/s) | Throughput (bytes/s) |
|---|--------------|--------|-----------|-----------|--------------|------------|--------------------|--------------------|
| 0 | Baseline (no patches) | ✅ PASSED | 2026-04-29 13:57:43 UTC | 25,034,075 | 15,680 | 00:02:32.9732304 | 168,234 | 25.16 MB/s |
| 1 | +01-fix-pattern-to-regex | ✅ PASSED | 2026-04-29 14:00:49 UTC | 25,034,075 | 15,680 | 00:03:00.2980752 | 141,881 | 21.22 MB/s |
| 2 | +02-parameterized-metadata-queries | ✅ PASSED | 2026-04-29 14:05:02 UTC | 25,034,075 | 15,680 | 00:04:07.8554940 | 103,053 | 15.41 MB/s |
| 3 | +03-retry-wallclock-timeout | ✅ PASSED | 2026-04-29 14:12:24 UTC | 25,034,075 | 15,680 | 00:07:09.6478452 | 58,855 | 8.80 MB/s |
| 4 | +04-persist-detected-project-id | ✅ PASSED | 2026-04-29 14:20:20 UTC | 25,034,075 | 15,680 | 00:07:49.4266653 | 53,862 | 8.06 MB/s |
| 5 | +05-skip-credential-recreation | ✅ PASSED | 2026-04-29 14:27:26 UTC | 25,034,075 | 15,680 | 00:07:00.0680025 | 60,337 | 9.02 MB/s |
| 6 | +06-reuse-grpc-channel | ❌ FAILED | 2026-04-29 14:27:32 UTC | - | - | - | - | - |
| 7 | +07-async-first-execute | ❌ FAILED | 2026-04-29 14:27:36 UTC | - | - | - | - | - |
| 8 | +08-parallel-getobjects | ❌ FAILED | 2026-04-29 14:27:42 UTC | - | - | - | - | - |
| 9 | +09-batch-information-schema | ❌ FAILED | 2026-04-29 14:27:47 UTC | - | - | - | - | - |
| 10 | +10-reduce-metadata-memory | ❌ FAILED | 2026-04-29 14:27:52 UTC | - | - | - | - | - |
| 11 | +11-cache-grpc-channel-per-connection | ❌ FAILED | 2026-04-29 14:27:56 UTC | - | - | - | - | - |
| 12 | +12-parallel-getjob-multi-statement | ❌ FAILED | 2026-04-29 14:28:02 UTC | - | - | - | - | - |
| 13 | +13-fix-sanitize-regex-anchor | ❌ FAILED | 2026-04-29 14:28:06 UTC | - | - | - | - | - |
| 14 | +14-fix-httpclient-leak-getaccesstoken | ❌ FAILED | 2026-04-29 14:28:10 UTC | - | - | - | - | - |
| 15 | +15-async-dispose-readrowsstream | ❌ FAILED | 2026-04-29 14:28:15 UTC | - | - | - | - | - |
| 16 | +16-enable-arrow-lz4-compression | ❌ FAILED | 2026-04-29 14:28:20 UTC | - | - | - | - | - |

## Detailed Results

### Baseline (no patches)

**Completed:** 2026-04-29 13:57:43 UTC
**Wall-clock time:** 160s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 464 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 464 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.07]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.08]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0192623
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:04.1485385
Schema: 18 columns
  realdatecol: Timestamp
  date: String
  event_name: String
  FilialNr: String
  category: String
  action: String
  area: String
  sign_up_login_place: String
  error_message: String
  email_hash: String
  status: String
  TotalEvents: Int64
  DAUs: Int64
  Visits: Int64
  Definition: String
  dsgvo_consent: String
  reason: String
  step: String
--- Timing ---
  Connection:       00:00:00.0192623
  Query execution:  00:00:04.1485385
  Time to 1st batch:00:00:00.4097039
  Data transfer:    00:02:28.8047580
  Total:            00:02:32.9732304
--- Volume ---
  Total rows:       25,034,075
  Total batches:    15,680
  Columns:          18
  Total bytes (est):3,925,666,118 (3.66 GB)
  Avg batch size:   1,597 rows
  Min batch size:   47 rows
  Max batch size:   1,600 rows
--- Throughput ---
  Rows/sec (read):  168,234
  Bytes/sec (read): 26,381,321 (25.16 MB/s)
  Rows/sec (total): 163,650
  Bytes/sec (total):25,662,439 (24.47 MB/s)
==========================================================
[xUnit.net 00:02:33.14]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport [2 m 33 s]
  Standard Output Messages:
 ==========================================================
 Environment: edag-dm-poc-01
 Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
 ==========================================================
 Connection time: 00:00:00.0192623
 Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
 Query execution time: 00:00:04.1485385
 Schema: 18 columns
   realdatecol: Timestamp
   date: String
   event_name: String
   FilialNr: String
   category: String
   action: String
   area: String
   sign_up_login_place: String
   error_message: String
   email_hash: String
   status: String
   TotalEvents: Int64
   DAUs: Int64
   Visits: Int64
   Definition: String
   dsgvo_consent: String
   reason: String
   step: String
 
 --- Timing ---
   Connection:       00:00:00.0192623
   Query execution:  00:00:04.1485385
   Time to 1st batch:00:00:00.4097039
   Data transfer:    00:02:28.8047580
   Total:            00:02:32.9732304
 
 --- Volume ---
   Total rows:       25,034,075
   Total batches:    15,680
   Columns:          18
   Total bytes (est):3,925,666,118 (3.66 GB)
   Avg batch size:   1,597 rows
   Min batch size:   47 rows
   Max batch size:   1,600 rows
 
 --- Throughput ---
   Rows/sec (read):  168,234
   Bytes/sec (read): 26,381,321 (25.16 MB/s)
   Rows/sec (total): 163,650
   Bytes/sec (total):25,662,439 (24.47 MB/s)
 ==========================================================
 



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 2.5578 Minutes
```
</details>

### Patch 1: 01-fix-pattern-to-regex

**Cumulative patches:** 01 through 01
**Completed:** 2026-04-29 14:00:49 UTC
**Wall-clock time:** 186s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 427 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 427 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.06]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.08]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0200803
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:03.8327246
Schema: 18 columns
  realdatecol: Timestamp
  date: String
  event_name: String
  FilialNr: String
  category: String
  action: String
  area: String
  sign_up_login_place: String
  error_message: String
  email_hash: String
  status: String
  TotalEvents: Int64
  DAUs: Int64
  Visits: Int64
  Definition: String
  dsgvo_consent: String
  reason: String
  step: String
--- Timing ---
  Connection:       00:00:00.0200803
  Query execution:  00:00:03.8327246
  Time to 1st batch:00:00:00.2708340
  Data transfer:    00:02:56.4441680
  Total:            00:03:00.2980752
--- Volume ---
  Total rows:       25,034,075
  Total batches:    15,680
  Columns:          18
  Total bytes (est):3,925,666,118 (3.66 GB)
  Avg batch size:   1,597 rows
  Min batch size:   47 rows
  Max batch size:   1,600 rows
--- Throughput ---
  Rows/sec (read):  141,881
  Bytes/sec (read): 22,248,772 (21.22 MB/s)
  Rows/sec (total): 138,848
  Bytes/sec (total):21,773,200 (20.76 MB/s)
==========================================================
[xUnit.net 00:03:00.45]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport [3 m]
  Standard Output Messages:
 ==========================================================
 Environment: edag-dm-poc-01
 Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
 ==========================================================
 Connection time: 00:00:00.0200803
 Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
 Query execution time: 00:00:03.8327246
 Schema: 18 columns
   realdatecol: Timestamp
   date: String
   event_name: String
   FilialNr: String
   category: String
   action: String
   area: String
   sign_up_login_place: String
   error_message: String
   email_hash: String
   status: String
   TotalEvents: Int64
   DAUs: Int64
   Visits: Int64
   Definition: String
   dsgvo_consent: String
   reason: String
   step: String
 
 --- Timing ---
   Connection:       00:00:00.0200803
   Query execution:  00:00:03.8327246
   Time to 1st batch:00:00:00.2708340
   Data transfer:    00:02:56.4441680
   Total:            00:03:00.2980752
 
 --- Volume ---
   Total rows:       25,034,075
   Total batches:    15,680
   Columns:          18
   Total bytes (est):3,925,666,118 (3.66 GB)
   Avg batch size:   1,597 rows
   Min batch size:   47 rows
   Max batch size:   1,600 rows
 
 --- Throughput ---
   Rows/sec (read):  141,881
   Bytes/sec (read): 22,248,772 (21.22 MB/s)
   Rows/sec (total): 138,848
   Bytes/sec (total):21,773,200 (20.76 MB/s)
 ==========================================================
 



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 3.0122 Minutes
```
</details>

### Patch 2: 02-parameterized-metadata-queries

**Cumulative patches:** 01 through 02
**Completed:** 2026-04-29 14:05:02 UTC
**Wall-clock time:** 253s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 439 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 437 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.06]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.08]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0205402
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:04.9101552
Schema: 18 columns
  realdatecol: Timestamp
  date: String
  event_name: String
  FilialNr: String
  category: String
  action: String
  area: String
  sign_up_login_place: String
  error_message: String
  email_hash: String
  status: String
  TotalEvents: Int64
  DAUs: Int64
  Visits: Int64
  Definition: String
  dsgvo_consent: String
  reason: String
  step: String
--- Timing ---
  Connection:       00:00:00.0205402
  Query execution:  00:00:04.9101552
  Time to 1st batch:00:00:00.2654834
  Data transfer:    00:04:02.9233724
  Total:            00:04:07.8554940
--- Volume ---
  Total rows:       25,034,075
  Total batches:    15,680
  Columns:          18
  Total bytes (est):3,925,666,118 (3.66 GB)
  Avg batch size:   1,597 rows
  Min batch size:   47 rows
  Max batch size:   1,600 rows
--- Throughput ---
  Rows/sec (read):  103,053
  Bytes/sec (read): 16,160,101 (15.41 MB/s)
  Rows/sec (total): 101,003
  Bytes/sec (total):15,838,528 (15.10 MB/s)
==========================================================
[xUnit.net 00:04:08.01]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport [4 m 7 s]
  Standard Output Messages:
 ==========================================================
 Environment: edag-dm-poc-01
 Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
 ==========================================================
 Connection time: 00:00:00.0205402
 Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
 Query execution time: 00:00:04.9101552
 Schema: 18 columns
   realdatecol: Timestamp
   date: String
   event_name: String
   FilialNr: String
   category: String
   action: String
   area: String
   sign_up_login_place: String
   error_message: String
   email_hash: String
   status: String
   TotalEvents: Int64
   DAUs: Int64
   Visits: Int64
   Definition: String
   dsgvo_consent: String
   reason: String
   step: String
 
 --- Timing ---
   Connection:       00:00:00.0205402
   Query execution:  00:00:04.9101552
   Time to 1st batch:00:00:00.2654834
   Data transfer:    00:04:02.9233724
   Total:            00:04:07.8554940
 
 --- Volume ---
   Total rows:       25,034,075
   Total batches:    15,680
   Columns:          18
   Total bytes (est):3,925,666,118 (3.66 GB)
   Avg batch size:   1,597 rows
   Min batch size:   47 rows
   Max batch size:   1,600 rows
 
 --- Throughput ---
   Rows/sec (read):  103,053
   Bytes/sec (read): 16,160,101 (15.41 MB/s)
   Rows/sec (total): 101,003
   Bytes/sec (total):15,838,528 (15.10 MB/s)
 ==========================================================
 



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 4.1383 Minutes
```
</details>

### Patch 3: 03-retry-wallclock-timeout

**Cumulative patches:** 01 through 03
**Completed:** 2026-04-29 14:12:24 UTC
**Wall-clock time:** 441s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 6.42 sec).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 6.42 sec).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.07]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.08]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0220098
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:04.2743966
Schema: 18 columns
  realdatecol: Timestamp
  date: String
  event_name: String
  FilialNr: String
  category: String
  action: String
  area: String
  sign_up_login_place: String
  error_message: String
  email_hash: String
  status: String
  TotalEvents: Int64
  DAUs: Int64
  Visits: Int64
  Definition: String
  dsgvo_consent: String
  reason: String
  step: String
--- Timing ---
  Connection:       00:00:00.0220098
  Query execution:  00:00:04.2743966
  Time to 1st batch:00:00:00.3440253
  Data transfer:    00:07:05.3507942
  Total:            00:07:09.6478452
--- Volume ---
  Total rows:       25,034,075
  Total batches:    15,680
  Columns:          18
  Total bytes (est):3,925,666,118 (3.66 GB)
  Avg batch size:   1,597 rows
  Min batch size:   47 rows
  Max batch size:   1,600 rows
--- Throughput ---
  Rows/sec (read):  58,855
  Bytes/sec (read): 9,229,244 (8.80 MB/s)
  Rows/sec (total): 58,266
  Bytes/sec (total):9,136,939 (8.71 MB/s)
==========================================================
[xUnit.net 00:07:09.81]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport [7 m 9 s]
  Standard Output Messages:
 ==========================================================
 Environment: edag-dm-poc-01
 Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
 ==========================================================
 Connection time: 00:00:00.0220098
 Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
 Query execution time: 00:00:04.2743966
 Schema: 18 columns
   realdatecol: Timestamp
   date: String
   event_name: String
   FilialNr: String
   category: String
   action: String
   area: String
   sign_up_login_place: String
   error_message: String
   email_hash: String
   status: String
   TotalEvents: Int64
   DAUs: Int64
   Visits: Int64
   Definition: String
   dsgvo_consent: String
   reason: String
   step: String
 
 --- Timing ---
   Connection:       00:00:00.0220098
   Query execution:  00:00:04.2743966
   Time to 1st batch:00:00:00.3440253
   Data transfer:    00:07:05.3507942
   Total:            00:07:09.6478452
 
 --- Volume ---
   Total rows:       25,034,075
   Total batches:    15,680
   Columns:          18
   Total bytes (est):3,925,666,118 (3.66 GB)
   Avg batch size:   1,597 rows
   Min batch size:   47 rows
   Max batch size:   1,600 rows
 
 --- Throughput ---
   Rows/sec (read):  58,855
   Bytes/sec (read): 9,229,244 (8.80 MB/s)
   Rows/sec (total): 58,266
   Bytes/sec (total):9,136,939 (8.71 MB/s)
 ==========================================================
 



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 7.1683 Minutes
```
</details>

### Patch 4: 04-persist-detected-project-id

**Cumulative patches:** 01 through 04
**Completed:** 2026-04-29 14:20:20 UTC
**Wall-clock time:** 475s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 482 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 482 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.05]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.07]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.09]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0299010
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:04.6163679
Schema: 18 columns
  realdatecol: Timestamp
  date: String
  event_name: String
  FilialNr: String
  category: String
  action: String
  area: String
  sign_up_login_place: String
  error_message: String
  email_hash: String
  status: String
  TotalEvents: Int64
  DAUs: Int64
  Visits: Int64
  Definition: String
  dsgvo_consent: String
  reason: String
  step: String
--- Timing ---
  Connection:       00:00:00.0299010
  Query execution:  00:00:04.6163679
  Time to 1st batch:00:00:00.4610589
  Data transfer:    00:07:44.7787884
  Total:            00:07:49.4266653
--- Volume ---
  Total rows:       25,034,075
  Total batches:    15,680
  Columns:          18
  Total bytes (est):3,925,666,118 (3.66 GB)
  Avg batch size:   1,597 rows
  Min batch size:   47 rows
  Max batch size:   1,600 rows
--- Throughput ---
  Rows/sec (read):  53,862
  Bytes/sec (read): 8,446,311 (8.06 MB/s)
  Rows/sec (total): 53,329
  Bytes/sec (total):8,362,682 (7.98 MB/s)
==========================================================
[xUnit.net 00:07:49.66]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport [7 m 49 s]
  Standard Output Messages:
 ==========================================================
 Environment: edag-dm-poc-01
 Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
 ==========================================================
 Connection time: 00:00:00.0299010
 Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
 Query execution time: 00:00:04.6163679
 Schema: 18 columns
   realdatecol: Timestamp
   date: String
   event_name: String
   FilialNr: String
   category: String
   action: String
   area: String
   sign_up_login_place: String
   error_message: String
   email_hash: String
   status: String
   TotalEvents: Int64
   DAUs: Int64
   Visits: Int64
   Definition: String
   dsgvo_consent: String
   reason: String
   step: String
 
 --- Timing ---
   Connection:       00:00:00.0299010
   Query execution:  00:00:04.6163679
   Time to 1st batch:00:00:00.4610589
   Data transfer:    00:07:44.7787884
   Total:            00:07:49.4266653
 
 --- Volume ---
   Total rows:       25,034,075
   Total batches:    15,680
   Columns:          18
   Total bytes (est):3,925,666,118 (3.66 GB)
   Avg batch size:   1,597 rows
   Min batch size:   47 rows
   Max batch size:   1,600 rows
 
 --- Throughput ---
   Rows/sec (read):  53,862
   Bytes/sec (read): 8,446,311 (8.06 MB/s)
   Rows/sec (total): 53,329
   Bytes/sec (total):8,362,682 (7.98 MB/s)
 ==========================================================
 



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 7.8329 Minutes
```
</details>

### Patch 5: 05-skip-credential-recreation

**Cumulative patches:** 01 through 05
**Completed:** 2026-04-29 14:27:26 UTC
**Wall-clock time:** 425s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 460 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 460 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.07]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.09]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0264660
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:05.1381571
Schema: 18 columns
  realdatecol: Timestamp
  date: String
  event_name: String
  FilialNr: String
  category: String
  action: String
  area: String
  sign_up_login_place: String
  error_message: String
  email_hash: String
  status: String
  TotalEvents: Int64
  DAUs: Int64
  Visits: Int64
  Definition: String
  dsgvo_consent: String
  reason: String
  step: String
--- Timing ---
  Connection:       00:00:00.0264660
  Query execution:  00:00:05.1381571
  Time to 1st batch:00:00:00.3562295
  Data transfer:    00:06:54.9024826
  Total:            00:07:00.0680025
--- Volume ---
  Total rows:       25,034,075
  Total batches:    15,680
  Columns:          18
  Total bytes (est):3,925,666,118 (3.66 GB)
  Avg batch size:   1,597 rows
  Min batch size:   47 rows
  Max batch size:   1,600 rows
--- Throughput ---
  Rows/sec (read):  60,337
  Bytes/sec (read): 9,461,660 (9.02 MB/s)
  Rows/sec (total): 59,595
  Bytes/sec (total):9,345,311 (8.91 MB/s)
==========================================================
[xUnit.net 00:07:00.25]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport [7 m]
  Standard Output Messages:
 ==========================================================
 Environment: edag-dm-poc-01
 Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
 ==========================================================
 Connection time: 00:00:00.0264660
 Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
 Query execution time: 00:00:05.1381571
 Schema: 18 columns
   realdatecol: Timestamp
   date: String
   event_name: String
   FilialNr: String
   category: String
   action: String
   area: String
   sign_up_login_place: String
   error_message: String
   email_hash: String
   status: String
   TotalEvents: Int64
   DAUs: Int64
   Visits: Int64
   Definition: String
   dsgvo_consent: String
   reason: String
   step: String
 
 --- Timing ---
   Connection:       00:00:00.0264660
   Query execution:  00:00:05.1381571
   Time to 1st batch:00:00:00.3562295
   Data transfer:    00:06:54.9024826
   Total:            00:07:00.0680025
 
 --- Volume ---
   Total rows:       25,034,075
   Total batches:    15,680
   Columns:          18
   Total bytes (est):3,925,666,118 (3.66 GB)
   Avg batch size:   1,597 rows
   Min batch size:   47 rows
   Max batch size:   1,600 rows
 
 --- Throughput ---
   Rows/sec (read):  60,337
   Bytes/sec (read): 9,461,660 (9.02 MB/s)
   Rows/sec (total): 59,595
   Bytes/sec (total):9,345,311 (8.91 MB/s)
 ==========================================================
 



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 7.0092 Minutes
```
</details>

### Patch 6: 06-reuse-grpc-channel

**Cumulative patches:** 01 through 06
**Completed:** 2026-04-29 14:27:32 UTC
**Wall-clock time:** 4s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 470 ms).
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 470 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/TokenProtectedReadClient.cs(73,35): error CS1061: 'BigQueryReadClient' does not contain a definition for 'ShutdownChannelAsync' and no accessible extension method 'ShutdownChannelAsync' accepting a first argument of type 'BigQueryReadClient' could be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 7: 07-async-first-execute

**Cumulative patches:** 01 through 07
**Completed:** 2026-04-29 14:27:36 UTC
**Wall-clock time:** 3s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 440 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 439 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/TokenProtectedReadClient.cs(73,35): error CS1061: 'BigQueryReadClient' does not contain a definition for 'ShutdownChannelAsync' and no accessible extension method 'ShutdownChannelAsync' accepting a first argument of type 'BigQueryReadClient' could be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 8: 08-parallel-getobjects

**Cumulative patches:** 01 through 08
**Completed:** 2026-04-29 14:27:42 UTC
**Wall-clock time:** 4s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 585 ms).
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 585 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/TokenProtectedReadClient.cs(73,35): error CS1061: 'BigQueryReadClient' does not contain a definition for 'ShutdownChannelAsync' and no accessible extension method 'ShutdownChannelAsync' accepting a first argument of type 'BigQueryReadClient' could be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 9: 09-batch-information-schema

**Cumulative patches:** 01 through 09
**Completed:** 2026-04-29 14:27:47 UTC
**Wall-clock time:** 4s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 525 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 525 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/TokenProtectedReadClient.cs(73,35): error CS1061: 'BigQueryReadClient' does not contain a definition for 'ShutdownChannelAsync' and no accessible extension method 'ShutdownChannelAsync' accepting a first argument of type 'BigQueryReadClient' could be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 10: 10-reduce-metadata-memory

**Cumulative patches:** 01 through 10
**Completed:** 2026-04-29 14:27:52 UTC
**Wall-clock time:** 4s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 489 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 489 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 11: 11-cache-grpc-channel-per-connection

**Cumulative patches:** 01 through 11
**Completed:** 2026-04-29 14:27:56 UTC
**Wall-clock time:** 3s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 502 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 502 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 12: 12-parallel-getjob-multi-statement

**Cumulative patches:** 01 through 12
**Completed:** 2026-04-29 14:28:02 UTC
**Wall-clock time:** 4s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 540 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 540 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 13: 13-fix-sanitize-regex-anchor

**Cumulative patches:** 01 through 13
**Completed:** 2026-04-29 14:28:06 UTC
**Wall-clock time:** 3s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 475 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 475 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 14: 14-fix-httpclient-leak-getaccesstoken

**Cumulative patches:** 01 through 14
**Completed:** 2026-04-29 14:28:10 UTC
**Wall-clock time:** 3s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 452 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 452 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 15: 15-async-dispose-readrowsstream

**Cumulative patches:** 01 through 15
**Completed:** 2026-04-29 14:28:15 UTC
**Wall-clock time:** 3s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 439 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 439 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

### Patch 16: 16-enable-arrow-lz4-compression

**Cumulative patches:** 01 through 16
**Completed:** 2026-04-29 14:28:20 UTC
**Wall-clock time:** 3s

<details>
<summary>Full test output</summary>

```
  Determining projects to restore...
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 433 ms).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 433 ms).
  4 of 6 projects are up-to-date for restore.
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
/repo/csharp/src/BigQueryInfoArrowStream.cs(73,26): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
/repo/csharp/src/BigQueryInfoArrowStream.cs(83,13): error CS0246: The type or namespace name 'GetObjectsDepth' could not be found (are you missing a using directive or an assembly reference?) [/repo/csharp/src/AdbcDrivers.BigQuery.csproj::TargetFramework=net8.0]
```
</details>

---
*Generated by `run-perf-suite.sh` on 2026-04-29 14:28:21 UTC*
