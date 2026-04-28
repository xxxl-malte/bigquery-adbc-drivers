# Docker Environment for the C# BigQuery ADBC Driver

Build, test, and develop the C# driver without installing the .NET SDK on your host.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose v2
- The git submodule must be initialized:
  ```sh
  git submodule update --init --recursive
  ```

## Services

| Service | Purpose |
|---|---|
| `build` | Compile the driver in Release mode |
| `test` | Run unit tests (no credentials needed) |
| `dev` | Interactive bash shell with live-mounted source |
| `integration-test` | Run full test suite against a real BigQuery instance |

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

Integration tests connect to a real BigQuery instance and require two things:

### 1. A test configuration file

Create a JSON config file based on the template at `test/Resources/bigqueryconfig.json`.
A minimal working example:

```json
{
    "testEnvironments": ["dev"],
    "shared": {
        "clientId": "YOUR_OAUTH_CLIENT_ID",
        "clientSecret": "YOUR_OAUTH_CLIENT_SECRET"
    },
    "environments": {
        "dev": {
            "projectId": "your-gcp-project-id",
            "clientId": "$ref:shared.clientId",
            "clientSecret": "$ref:shared.clientSecret",
            "refreshToken": "YOUR_REFRESH_TOKEN",
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

> **Tip:** Run `test/Resources/BigQueryData.sql` against your BigQuery instance first
> to create the expected test data.

See `test/readme.md` for the full list of configuration options including
`billingProjectId`, `scopes`, `queryTimeout`, `allowLargeResults`, and others.

### 2. Run with the config file mounted

```sh
# Point to your config file
export BIGQUERY_TEST_CONFIG_FILE=/path/to/your/bigqueryconfig.json

docker compose run --rm \
  -e BIGQUERY_TEST_CONFIG_FILE=/config/bigqueryconfig.json \
  -v "$BIGQUERY_TEST_CONFIG_FILE:/config/bigqueryconfig.json:ro" \
  integration-test
```

If your tests use **service account** authentication instead of OAuth, also mount the
service account key:

```sh
docker compose run --rm \
  -e BIGQUERY_TEST_CONFIG_FILE=/config/bigqueryconfig.json \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/service-account.json \
  -v "/path/to/bigqueryconfig.json:/config/bigqueryconfig.json:ro" \
  -v "/path/to/service-account.json:/secrets/service-account.json:ro" \
  integration-test
```

### Authentication types

The test config supports three `authenticationType` values:

| Type | Required fields |
|---|---|
| `user` | `clientId`, `clientSecret`, `refreshToken` |
| `service` | Service account JSON via `GOOGLE_APPLICATION_CREDENTIALS` |
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
