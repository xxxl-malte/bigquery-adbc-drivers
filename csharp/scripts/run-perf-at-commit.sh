#!/usr/bin/env bash
#
# run-perf-at-commit.sh — Run performance tests at a specific git commit
#
# Runs the BigQuery ADBC C# performance test against any commit using
# Docker volume mounts (no Dockerfile needed). Results are printed to
# stdout and optionally appended to PERFTESTS.md.
#
# Usage:
#   ./scripts/run-perf-at-commit.sh --config <path> [OPTIONS]
#
# Options:
#   --config PATH       Path to perfconfig.json (required)
#   --commit SHA        Git ref to test (default: HEAD)
#   --env-file PATH     Docker env file (default: ./.env)
#   --image NAME        Docker SDK image (default: mcr.microsoft.com/dotnet/sdk:8.0)
#   --append-to PATH    Append results to this file (e.g. PERFTESTS.md)
#   --help              Show this help message
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSHARP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$CSHARP_DIR/.." && pwd)"

CONFIG_FILE=""
COMMIT="HEAD"
ENV_FILE="$CSHARP_DIR/.env"
DOCKER_IMAGE="mcr.microsoft.com/dotnet/sdk:8.0"
APPEND_TO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     CONFIG_FILE="$2"; shift 2 ;;
        --commit)     COMMIT="$2"; shift 2 ;;
        --env-file)   ENV_FILE="$2"; shift 2 ;;
        --image)      DOCKER_IMAGE="$2"; shift 2 ;;
        --append-to)  APPEND_TO="$2"; shift 2 ;;
        --help)
            sed -n '3,18p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: --config is required" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
COMMIT_SHA="$(cd "$REPO_ROOT" && git rev-parse "$COMMIT")"
COMMIT_SHORT="${COMMIT_SHA:0:8}"

echo "Running perf test at commit $COMMIT_SHORT ($COMMIT_SHA)"

# ----- pull Docker image -----
echo "Pulling Docker image: $DOCKER_IMAGE ..."
docker pull "$DOCKER_IMAGE" --quiet >/dev/null 2>&1 || true

# ----- create worktree -----
WORKTREE_DIR="$(mktemp -d)"
cleanup() {
    cd "$REPO_ROOT"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
}
trap cleanup EXIT

cd "$REPO_ROOT"
git worktree add "$WORKTREE_DIR" "$COMMIT_SHA" --detach --quiet
echo "Worktree created at $WORKTREE_DIR"

# ----- initialize submodule -----
WT_CSHARP="$WORKTREE_DIR/csharp"
MAIN_SUBMODULE="$CSHARP_DIR/arrow-adbc"

if [[ -d "$MAIN_SUBMODULE/.git" ]] || [[ -f "$MAIN_SUBMODULE/.git" ]]; then
    echo "Copying submodule arrow-adbc into worktree..."
    rm -rf "$WT_CSHARP/arrow-adbc"
    cp -R "$MAIN_SUBMODULE" "$WT_CSHARP/arrow-adbc"
else
    echo "Initializing submodule in worktree..."
    cd "$WORKTREE_DIR"
    git submodule update --init --recursive
fi

# ----- copy perf infrastructure -----
# The perf/ directory may not exist at the target commit
echo "Copying perf test infrastructure..."
rm -rf "$WT_CSHARP/perf"
cp -R "$CSHARP_DIR/perf" "$WT_CSHARP/perf"

# ----- clean build artifacts -----
rm -rf "$WT_CSHARP/src/obj" "$WT_CSHARP/src/bin"
rm -rf "$WT_CSHARP/perf/obj" "$WT_CSHARP/perf/bin"
rm -rf "$WT_CSHARP/artifacts/AdbcDrivers.BigQuery"
rm -rf "$WT_CSHARP/artifacts/AdbcDrivers.BigQuery.Perf"

# ----- prepare Docker args -----
env_args=()
if [[ -f "$ENV_FILE" ]]; then
    env_args+=(--env-file "$ENV_FILE")
fi

# Mount GCP credentials if available
gcp_cred_args=()
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] && [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    gcp_cred_args+=(-v "$GOOGLE_APPLICATION_CREDENTIALS:/repo/gcp-credentials.json:ro")
    gcp_cred_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
elif [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
    gcp_cred_args+=(-v "$HOME/.config/gcloud/application_default_credentials.json:/repo/gcp-credentials.json:ro")
    gcp_cred_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
fi

# ----- run build + test -----
echo "Building & running perf test..."
OUTPUT_FILE="$(mktemp)"
start_time=$(date +%s)

if docker run --rm \
    ${env_args[@]+"${env_args[@]}"} \
    ${gcp_cred_args[@]+"${gcp_cred_args[@]}"} \
    -v nuget-perf-cache:/root/.nuget/packages \
    -e "BIGQUERY_PERF_CONFIG_FILE=/repo/perfconfig.json" \
    -v "$WT_CSHARP:/repo/csharp" \
    -v "$CONFIG_FILE:/repo/perfconfig.json:ro" \
    -w /repo/csharp \
    "$DOCKER_IMAGE" \
    dotnet test perf/AdbcDrivers.BigQuery.Perf.csproj \
        -c Release \
        --logger "console;verbosity=detailed" \
        --filter "FullyQualifiedName=AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport" \
    > "$OUTPUT_FILE" 2>&1; then

    end_time=$(date +%s)

    # Check for no-tests-executed or skipped tests (false positive exit 0)
    if grep -qE "Total tests:.*0[^0-9]" "$OUTPUT_FILE" 2>/dev/null && \
       ! grep -qE "Passed:[[:space:]]*[1-9]" "$OUTPUT_FILE" 2>/dev/null; then
        echo "⚠️  No tests executed (exit 0 but 0 tests passed)"
        STATUS="NO_TESTS"
    elif grep -qE "Skipped:[[:space:]]*[1-9]" "$OUTPUT_FILE" 2>/dev/null && \
         ! grep -qE "Passed:[[:space:]]*[1-9]" "$OUTPUT_FILE" 2>/dev/null; then
        echo "⚠️  Test skipped (missing credentials or config)"
        STATUS="SKIPPED"
    else
        echo "✅ Test passed ($((end_time - start_time))s)"
        STATUS="PASSED"
    fi
else
    end_time=$(date +%s)
    if grep -qE "Build FAILED|Error\(s\)" "$OUTPUT_FILE" 2>/dev/null && \
       ! grep -qE "Total tests:" "$OUTPUT_FILE" 2>/dev/null; then
        echo "❌ Build FAILED"
        STATUS="BUILD_FAILED"
    else
        echo "❌ Test FAILED ($((end_time - start_time))s)"
        STATUS="FAILED"
    fi
fi

echo ""
echo "--- Output ---"
cat "$OUTPUT_FILE"

# ----- optionally append to PERFTESTS.md -----
if [[ -n "$APPEND_TO" ]]; then
    {
        echo ""
        echo "### Ad-hoc run: commit \`$COMMIT_SHORT\`"
        echo ""
        echo "**Full SHA:** \`$COMMIT_SHA\`"
        echo "**Date:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "**Status:** $STATUS"
        echo "**Wall-clock:** $((end_time - start_time))s"
        echo ""
        echo "<details>"
        echo "<summary>Full output</summary>"
        echo ""
        echo '```'
        cat "$OUTPUT_FILE"
        echo '```'
        echo "</details>"
        echo ""
    } >> "$APPEND_TO"
    echo ""
    echo "Results appended to $APPEND_TO"
fi

rm -f "$OUTPUT_FILE"
