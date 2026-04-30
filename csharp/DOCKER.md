# Docker Environment for the C# BigQuery ADBC Driver

Build, test, and develop the C# driver without installing the .NET SDK on your host.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose v2
- The git submodule must be initialized:
  ```sh
  git submodule update --init --recursive
  ```

## Environment Setup

All credential paths are configured through a `.env` file read by docker-compose.

```sh
cd csharp/
cp .env.sample .env
```

Edit `.env` and set the paths to your credential/config files:

```dotenv
GOOGLE_APPLICATION_CREDENTIALS=./secrets/service-account.json
BIGQUERY_TEST_CONFIG_FILE=./secrets/bigqueryconfig.json
BIGQUERY_PERF_CONFIG_FILE=./secrets/perfconfig.json
```

> **Note:** `.env` and `secrets/` are gitignored — they are never committed.

## Services

| Service | Purpose |
|---|---|
| `build` | Compile the driver in Release mode |
| `test` | Run unit tests (no credentials needed) |
| `dev` | Interactive bash shell with live-mounted source |
| `integration-test` | Run full test suite against a real BigQuery instance |
| `perf-test` | Run performance benchmarks against a real BigQuery table |

## Quick Start

```sh
cd csharp/

# Build the driver
docker compose run --rm build

# Run unit tests
docker compose run --rm test

# Run a specific test class
docker compose run --rm test --filter "FullyQualifiedName~BigQueryConnectionTests"

# Open an interactive shell
docker compose run --rm dev
```

## Running Integration Tests

Integration tests connect to a real BigQuery instance and require:

1. **A test configuration file** — based on `test/Resources/bigqueryconfig.json`
2. **Paths set in `.env`** — so docker-compose can mount them into the container

### 1. Create a test configuration file

Place it in `secrets/` (gitignored). Minimal example:

```json
{
    "testEnvironments": ["dev"],
    "environments": {
        "dev": {
            "projectId": "your-gcp-project-id",
            "authenticationType": "service",
            "maxStreamCount": 1,
            "metadata": {
                "catalog": "your-gcp-project-id",
                "schema": "your_dataset",
                "table": "your_table",
                "expectedColumnCount": 10
            },
            "query": "SELECT * FROM `your-gcp-project-id.your_dataset.your_table` LIMIT 10",
            "expectedResults": 10
        }
    }
}
```

For **OAuth (user)** auth, add `clientId`, `clientSecret`, and `refreshToken` directly
in the environment block (or use the `shared` / `$ref:shared.*` pattern — see
`test/readme.md` for full details).

> **Tip:** Run `test/Resources/BigQueryData.sql` against your BigQuery instance first
> to create the expected test data.

```bash
 gcloud auth application-default login \
   --scopes=https://www.googleapis.com/auth/bigquery
```

### 2. Set paths in `.env`

```dotenv
GOOGLE_APPLICATION_CREDENTIALS=./secrets/service-account.json
BIGQUERY_TEST_CONFIG_FILE=./secrets/bigqueryconfig.json
```

### 3. Run

```sh
docker compose run --rm integration-test
```

### Authentication types

| Type | Required fields in test config JSON |
|---|---|
| `user` | `clientId`, `clientSecret`, `refreshToken` |
| `service` | `jsonCredential` in JSON, or mount service account via `GOOGLE_APPLICATION_CREDENTIALS` |
| `aad` | `accessToken`, `audience` (Microsoft Entra) |

## Development Shell

The `dev` service mounts `src/` and `test/` from your host for live editing:

```sh
docker compose run --rm dev

# Inside the container:
dotnet build src/AdbcDrivers.BigQuery.csproj -c Debug
dotnet test test/AdbcDrivers.BigQuery.Tests.csproj -c Debug
```

## Rebuilding

After changing source files (outside the `dev` service), rebuild images:

```sh
docker compose build
```

## Running Performance Tests

Performance tests measure full table import throughput. They are a **separate** project
under `perf/` and do not run with the integration tests.

### 1. Create a perf config file

Copy `perf/perfconfig.sample.json` and fill in your details:

```json
{
    "environments": [
        {
            "name": "default",
            "projectId": "your-gcp-project-id",
            "authenticationType": "service",
            "jsonCredential": "{ ... service account JSON ... }",
            "catalog": "your-gcp-project-id",
            "schema": "your_dataset",
            "table": "your_table",
            "maxStreamCount": 0,
            "allowLargeResults": false,
            "iterations": 5
        }
    ]
}
```

| Field | Description |
|---|---|
| `catalog` | BigQuery project containing the table |
| `schema` | BigQuery dataset |
| `table` | Table to import (SELECT *) |
| `maxStreamCount` | Parallel read streams (`0` = server default) |
| `iterations` | Number of repeated runs for the `MeasureFullTableImportRepeated` and `MeasureGetObjectsRepeated` tests (default 5 if unset). The orchestrator scripts use these to compute avg ± stddev and Δ vs baseline. |

### 2. Set the path in `.env`

```dotenv
BIGQUERY_PERF_CONFIG_FILE=./secrets/perfconfig.json
```

### 3. Run the perf tests

```sh
docker compose run --rm perf-test
```

To run a specific test:

```sh
docker compose run --rm perf-test \
  --filter "FullyQualifiedName~MeasureFullTableImport"
```

### Test descriptions

| Test | What it measures |
|---|---|
| `MeasureFullTableImport` | Single run with detailed phase breakdown (connect, query, read) and throughput stats |
| `MeasureFullTableImportRepeated` | Multiple runs with min/max/avg/stddev statistics |

## Testing an Older Commit

The simplest way to benchmark an older commit is with the provided script:

```sh
cd csharp/
./scripts/run-perf-at-commit.sh \
  --config perf/perfconfig.json \
  --commit <sha|tag|branch> \
  --append-to ./PERFTESTS.md
```

This handles worktree creation, submodule copying, credential mounting, and cleanup
automatically. Results print to stdout and optionally append to PERFTESTS.md.

### Manual approach

If you need more control, you can set up a worktree manually:

```sh
# 1. Create a worktree checked out at the target commit
git worktree add /tmp/bq-old <commit-hash> --detach
cd /tmp/bq-old

# 2. Copy the submodule (faster than re-cloning)
cp -R ~/Projects/bigquery/csharp/arrow-adbc /tmp/bq-old/csharp/arrow-adbc

# 3. Copy perf infrastructure (may not exist at that commit)
cp -R ~/Projects/bigquery/csharp/perf /tmp/bq-old/csharp/perf

# 4. Run via Docker volume mount
docker run --rm \
  -e "BIGQUERY_PERF_CONFIG_FILE=/repo/perfconfig.json" \
  -e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json" \
  -v "/tmp/bq-old/csharp:/repo/csharp" \
  -v "$PWD/perf/perfconfig.json:/repo/perfconfig.json:ro" \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/repo/gcp-credentials.json:ro" \
  -w /repo/csharp \
  mcr.microsoft.com/dotnet/sdk:8.0 \
  dotnet test perf/AdbcDrivers.BigQuery.Perf.csproj -c Release \
    --logger "console;verbosity=detailed" \
    --filter "FullyQualifiedName=AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport"

# 5. Clean up
cd ~/Projects/bigquery
git worktree remove /tmp/bq-old
```

> **Tip:** You can have multiple worktrees at the same time (e.g. `/tmp/bq-v1` and
> `/tmp/bq-v2`) to compare results across commits side by side.

## Stacked Patch Performance Suite

The `patches/` directory contains 16 performance patches. The `scripts/run-perf-suite.sh` script applies them incrementally
and measures the cumulative impact.

### Quick start

```sh
cd csharp/
./scripts/run-perf-suite.sh --config ./secrets/perfconfig.json
```

This will:
1. Create a git worktree at HEAD
2. Run a baseline perf test (no patches), repeated `iterations` times (default 5 — set
   per environment via `iterations` in `perfconfig.json`)
3. Apply patches 01–16 one at a time:
   - Patches whose effects only show on the *metadata path* (01, 02, 08, 09, 10, 13)
     are applied to keep the canonical stack intact, but their build+test is **skipped**
     and shown as ⏭️ `OTHER_PATH` in the report. Use `run-metadata-perf-suite.sh` to
     evaluate those.
   - All other patches run the repeated perf test on top of the cumulative stack.
4. Wait a cooldown period between *tested* runs to mitigate BigQuery throttling.
   The script peeks ahead and skips the cooldown if only filtered patches remain.
5. Generate `PERFTESTS.md` with:
   - A summary table including a **Δ vs Baseline ± stddev** column (positive % = patch
     is faster; the ± figure combines baseline and patch stddev as a rough propagation
     of uncertainty — not a formal CI).
   - Per-row detailed sections containing the full test output (per-iteration timings,
     min/max/avg/stddev, and the driver's throttle stats from `MultiArrowReader`).

### Options

```
--config PATH       Path to perfconfig.json (required)
--commit SHA        Test against a specific commit (default: HEAD)
--patches DIR       Patch directory (default: ./patches)
--output PATH       Output file (default: ./PERFTESTS.md)
--skip-baseline     Skip the baseline run
--only N            Only run up to patch N (0 = baseline only)
--env-file PATH     Path to .env file (default: ./.env)
--image NAME        Docker SDK image (default: mcr.microsoft.com/dotnet/sdk:8.0)
--cooldown SECS     Seconds to wait between runs (default: 60, 0 to disable)
```

### Throttle visibility

The BigQuery Storage Read API dynamically throttles per-connection throughput via
`ThrottleState.throttle_percent` (0–100) in each `ReadRowsResponse`. The driver
tracks and reports these stats after each data transfer:

- **Max throttle** — highest throttle % seen across all batches/streams
- **Avg throttle** — mean throttle % across all batches
- **Batches throttled** — count and percentage of batches with non-zero throttle

These appear in the per-row detailed sections of `PERFTESTS.md` (full test output)
but are **no longer columns in the summary table**: with `MeasureFullTableImportRepeated`
running multiple iterations per row, throttle stats are emitted once per iteration and
don't aggregate cleanly into a single number. Use `--cooldown` (default 60 s) to give
throttle state time to dissipate between rows; if you see suspicious deltas, inspect
the per-iteration throttle in the row's detail section.

### Credential handling

Both scripts automatically mount GCP credentials into the Docker container:

1. If `GOOGLE_APPLICATION_CREDENTIALS` env var is set and points to a file, that file is mounted
2. Otherwise, `~/.config/gcloud/application_default_credentials.json` is used if it exists
3. If your `perfconfig.json` has inline `jsonCredential`, no file mount is needed

To set up ADC credentials:

```sh
gcloud auth application-default login --scopes=https://www.googleapis.com/auth/bigquery
```

#### Running on a GCP VM

If running the perf scripts on a GCP VM (e.g. the `terraform/` setup) you may hit:

```
InvalidOperationException: No JSON credential provided in config and
GOOGLE_APPLICATION_CREDENTIALS environment variable is not set or file does not exist.
```

The perf test code (`perf/FullTableImportTest.cs`) only accepts a service-account
JSON credential — either inline as `jsonCredential` in `perfconfig.json`, or via a
file path in `GOOGLE_APPLICATION_CREDENTIALS`. Two important caveats on a VM:

- **The VM's attached service account / instance metadata server is not used.**
  The driver is invoked with `auth_type=service` + `auth_json_credential=<JSON>`;
  there is no metadata-server fallback path.
- **`gcloud auth application-default login` on the VM does not help.** It produces
  a *user* credential JSON (with `refresh_token` / `client_id`), which the
  `service` auth path will not accept. ADC works on your local Mac only because
  the script happens to find that file there — it does not mean the credential
  itself is compatible if the test ever needs to fall through.

To run on the VM, pick one of:

**Upload a service-account key and export the env var:**

```sh
# on the VM
export GOOGLE_APPLICATION_CREDENTIALS=/home/ubuntu/sa-key.json
./csharp/scripts/run-perf-suite.sh --config ./csharp/perf/perfconfig.json
```

**Inline the service-account JSON into `perfconfig.json`:**

Set the `jsonCredential` field to the full service-account JSON (escaped as a
single string per `perfconfig.sample.json`). The script then needs no host
credentials at all.

### Running a single commit

To benchmark any arbitrary commit without the patch suite:

```sh
./scripts/run-perf-at-commit.sh \
  --config ./secrets/perfconfig.json \
  --commit abc1234 \
  --append-to ./PERFTESTS.md
```

### Metadata-path suite (`run-metadata-perf-suite.sh`)

The data-path suite above (`run-perf-suite.sh`, calling
`MeasureFullTableImportRepeated`) does not enter the schema-discovery
code: `Connection.GetObjects` and the `INFORMATION_SCHEMA` queries it
fans out to. Patches that target those paths — currently 01, 02, 08,
09, 10, 13 — are filtered out (shown as ⏭️ `OTHER_PATH`) by
`run-perf-suite.sh`. Use the metadata-path suite to evaluate them:

```sh
cd csharp/
./scripts/run-metadata-perf-suite.sh --config ./secrets/perfconfig.json
```

Same options, same patch directory, same architecture as
`run-perf-suite.sh`. The two scripts apply a **symmetric filter** — each
applies all 16 patches (the canonical stack is preserved), but each
only runs the build+test for patches that affect *its* path:

| Script | Tests | Filters out (`OTHER_PATH`) |
|---|---|---|
| `run-perf-suite.sh` | data-path + shared (03, 04, 05, 06, 07, 11, 12, 14, 15, 16) | metadata-only (01, 02, 08, 09, 10, 13) |
| `run-metadata-perf-suite.sh` | metadata-path + shared (01, 02, 03, 04, 05, 08, 09, 10, 13, 14) | data-only (06, 07, 11, 12, 15, 16) |

Other differences for the metadata script:

- **Test:** `GetObjectsTest.MeasureGetObjectsRepeated` (`depth=All`,
  bounded by `catalog` and `schema` from the config — leave both empty
  to crawl the whole account; iterations from `perfconfig.json`,
  default 5).
- **Output:** `PERFTESTS_METADATA.md`.
- **Default cooldown:** 30 s (no Storage Read API throttling to worry
  about).
- **Summary columns:** `Iters | Catalogs | Avg (s) | Stddev (s) | Δ vs
  Baseline ± stddev | Peak WS`. The `Δ` column uses the same propagation
  -of-uncertainty formula as `run-perf-suite.sh`. Per-iteration timings,
  GetObjects time, and time-to-first-batch are still in the per-row
  detail sections (full test output).
- **No throughput / row-count columns** — those concepts don't apply to
  schema discovery the same way they do to a table import.

Patch-visibility cheat sheet for picking a target dataset:

| Patch | Visible when … |
|---|---|
| 09 (batch INFORMATION_SCHEMA) | dataset has many tables (≥ ~50) |
| 08 (parallel GetObjects) | catalog has many datasets |
| 10 (streaming GetObjects) | crawling many catalogs (`Peak WS` column) |
| 02 (parameterized queries) | many table/column lookups in one call |
| 01, 13 (regex fixes) | `catalog`/`schema` patterns contain wildcards |

### Patch order

| # | File | Description |
|---|------|-----------|
| 1 | `01-fix-pattern-to-regex.patch` | PatternToRegEx metacharacter escaping |
| 2 | `02-parameterized-metadata-queries.patch` | Parameterized SQL for metadata |
| 3 | `03-retry-wallclock-timeout.patch` | Wall-clock retry budget |
| 4 | `04-persist-detected-project-id.patch` | Persist detected project ID |
| 5 | `05-skip-credential-recreation.patch` | Skip redundant credential creation |
| 6 | `06-reuse-grpc-channel.patch` | Avoid gRPC client rebuild |
| 7 | `07-async-first-execute.patch` | Async-first Execute overrides |
| 8 | `08-parallel-getobjects.patch` | Async parallel GetObjects metadata |
| 9 | `09-batch-information-schema.patch` | Batch INFORMATION_SCHEMA queries |
| 10 | `10-reduce-metadata-memory.patch` | Streaming chunked metadata |
| 11 | `11-cache-grpc-channel-per-connection.patch` | Cache gRPC channel per connection |
| 12 | `12-parallel-getjob-multi-statement.patch` | Parallel GetJob for multi-statement |
| 13 | `13-fix-sanitize-regex-anchor.patch` | Fix Sanitize regex end-anchor |
| 14 | `14-fix-httpclient-leak-getaccesstoken.patch` | Fix HttpClient leak in GetAccessToken |
| 15 | `15-async-dispose-readrowsstream.patch` | Async dispose for ReadRowsStream |
| 16 | `16-enable-arrow-lz4-compression.patch` | Enable Arrow LZ4 compression |
