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
            "iterations": 3
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
| `iterations` | Number of repeated runs for the `MeasureFullTableImportRepeated` test |

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

To run tests or benchmarks against a previous version of the code without disturbing
your working branch, use a [git worktree](https://git-scm.com/docs/git-worktree):

```sh
# 1. Create a worktree checked out at the target commit
git worktree add /tmp/bq-old <commit-hash>
cd /tmp/bq-old
git submodule update --init --recursive

# 2. Copy the Docker infrastructure into the old tree
#    (it may not exist at that commit)
MAIN=~/Projects/bigquery/csharp
cp "$MAIN"/{Dockerfile,docker-compose.yml,.dockerignore,.env.sample} \
   /tmp/bq-old/csharp/
cp "$MAIN"/.env /tmp/bq-old/csharp/ 2>/dev/null   # only if you have one
cp -r "$MAIN"/perf /tmp/bq-old/csharp/

# 3. Build and run
cd /tmp/bq-old/csharp
docker compose build test
docker compose run --rm test

# 4. Clean up when done
cd ~/Projects/bigquery
git worktree remove /tmp/bq-old
```

> **Tip:** You can have multiple worktrees at the same time (e.g. `/tmp/bq-v1` and
> `/tmp/bq-v2`) to compare results across commits side by side.
