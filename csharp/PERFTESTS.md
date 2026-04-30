# Performance Test Results

**Commit:** `c9bad2478fb315ccdc718596cdb28df98f9840ce`
**Suite started:** 2026-04-30 17:34:18 UTC
**Last updated:** 2026-04-30 17:35:02 UTC
**Patches:** 16 applied incrementally
**Cooldown between runs:** 60s
**Connectivity check:** ✅ PASSED (2026-04-30 17:34:37 UTC)

## Summary

| # | Configuration | Status | Build (s) | Test (s) | Completed | Total Rows | Total Batches | Total Time | Throughput (rows/s) | Throughput (bytes/s) | Max Throttle | Avg Throttle |
|---|--------------|--------|----------|---------|-----------|-----------|--------------|------------|--------------------|--------------------|-------------|-------------|
| 0 | Baseline (no patches) | ⏳ PENDING | 5 | - | - | - | - | - | - | - | - | - |
| 1 | +01-fix-pattern-to-regex | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 2 | +02-parameterized-metadata-queries | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 3 | +03-retry-wallclock-timeout | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 4 | +04-persist-detected-project-id | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 5 | +05-skip-credential-recreation | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 6 | +06-reuse-grpc-channel | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 7 | +07-async-first-execute | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 8 | +08-parallel-getobjects | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 9 | +09-batch-information-schema | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 10 | +10-reduce-metadata-memory | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 11 | +11-cache-grpc-channel-per-connection | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 12 | +12-parallel-getjob-multi-statement | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 13 | +13-fix-sanitize-regex-anchor | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 14 | +14-fix-httpclient-leak-getaccesstoken | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 15 | +15-async-dispose-readrowsstream | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |
| 16 | +16-enable-arrow-lz4-compression | ⏳ PENDING | - | - | - | - | - | - | - | - | - | - |

## Detailed Results

### Preflight: Connectivity Check

**Status:** ✅ PASSED
**Completed:** 2026-04-30 17:34:37 UTC

<details>
<summary>Full preflight output</summary>

```
An issue was encountered verifying workloads. For more information, run "dotnet workload update".
  Determining projects to restore...
  Restored /repo/csharp/arrow-adbc/csharp/src/Client/Apache.Arrow.Adbc.Client.csproj (in 1 sec).
  Restored /repo/csharp/arrow-adbc/csharp/test/Apache.Arrow.Adbc.Tests/Apache.Arrow.Adbc.Testing.csproj (in 1.01 sec).
  Restored /repo/csharp/perf/AdbcDrivers.BigQuery.Perf.csproj (in 1.01 sec).
  Restored /repo/csharp/arrow-adbc/csharp/src/Telemetry/Traces/Listeners/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.csproj (in 1 sec).
  Restored /repo/csharp/src/AdbcDrivers.BigQuery.csproj (in 1.01 sec).
  Restored /repo/csharp/arrow-adbc/csharp/src/Apache.Arrow.Adbc/Apache.Arrow.Adbc.csproj (in 1 sec).
  Apache.Arrow.Adbc.Telemetry.Traces.Listeners -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Telemetry.Traces.Listeners/Release/net8.0/Apache.Arrow.Adbc.Telemetry.Traces.Listeners.dll
  Apache.Arrow.Adbc -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc/Release/net8.0/Apache.Arrow.Adbc.dll
  Apache.Arrow.Adbc.Client -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Client/Release/net8.0/Apache.Arrow.Adbc.Client.dll
  AdbcDrivers.BigQuery -> /repo/csharp/artifacts/AdbcDrivers.BigQuery/Release/net8.0/AdbcDrivers.BigQuery.dll
  Apache.Arrow.Adbc.Testing -> /repo/csharp/arrow-adbc/csharp/artifacts/Apache.Arrow.Adbc.Testing/Release/net8.0/Apache.Arrow.Adbc.Testing.dll
  AdbcDrivers.BigQuery.Perf -> /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll

Build succeeded.
    0 Warning(s)
    0 Error(s)

Time Elapsed 00:00:05.77
An issue was encountered verifying workloads. For more information, run "dotnet workload update".
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.06]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.07]   Starting:    AdbcDrivers.BigQuery.Perf
Connectivity check: edag-dm-poc-01 ...
  ✅ edag-dm-poc-01: OK (4.4s)
[xUnit.net 00:00:04.53]   Finished:    AdbcDrivers.BigQuery.Perf
  Passed AdbcDrivers.BigQuery.Perf.FullTableImportTest.VerifyConnectivity [4 s]
  Standard Output Messages:
 Connectivity check: edag-dm-poc-01 ...
   ✅ edag-dm-poc-01: OK (4.4s)



Test Run Successful.
Total tests: 1
     Passed: 1
 Total time: 4.7503 Seconds
```
</details>

### Baseline (no patches)

**Completed:** N/A
**Build time:** 5s
**Test time:** N/As

<details>
<summary>Full test output</summary>

```
An issue was encountered verifying workloads. For more information, run "dotnet workload update".
Test run for /repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll (.NETCoreApp,Version=v8.0)
VSTest version 17.11.1 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
/repo/csharp/artifacts/AdbcDrivers.BigQuery.Perf/Release/net8.0/AdbcDrivers.BigQuery.Perf.dll
[xUnit.net 00:00:00.00] xUnit.net VSTest Adapter v3.1.5+1b188a7b0a (64-bit .NET 8.0.26)
[xUnit.net 00:00:00.04]   Discovering: AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.06]   Discovered:  AdbcDrivers.BigQuery.Perf
[xUnit.net 00:00:00.07]   Starting:    AdbcDrivers.BigQuery.Perf
==========================================================
Environment: edag-dm-poc-01
Table: xxxl-np-edag-dm-poc-01.c_webtracking.general_daus_X10
==========================================================
Connection time: 00:00:00.0164508
Query: SELECT * FROM `xxxl-np-edag-dm-poc-01`.`c_webtracking`.`general_daus_X10`
Query execution time: 00:00:04.8985508
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
Attempting to cancel the build...
```
</details>

---
*Generated by `run-perf-suite.sh` on 2026-04-30 17:35:02 UTC*
