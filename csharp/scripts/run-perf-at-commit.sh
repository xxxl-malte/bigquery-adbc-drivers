#!/usr/bin/env bash
#
# run-perf-at-commit.sh — Run performance tests at a specific git commit
#
# This is a convenience wrapper around the Docker perf test that:
# 1. Creates a git worktree at the specified commit
# 2. Builds and runs the perf test via Docker
# 3. Outputs results to stdout and optionally appends to PERFTESTS.md
#
# Usage:
#   ./scripts/run-perf-at-commit.sh --config <path> --commit <sha|tag|branch>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSHARP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$CSHARP_DIR/.." && pwd)"

CONFIG_FILE=""
COMMIT="HEAD"
ENV_FILE="$CSHARP_DIR/.env"
APPEND_TO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     CONFIG_FILE="$2"; shift 2 ;;
        --commit)     COMMIT="$2"; shift 2 ;;
        --env-file)   ENV_FILE="$2"; shift 2 ;;
        --append-to)  APPEND_TO="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 --config <path> [--commit <ref>] [--env-file <path>] [--append-to <PERFTESTS.md>]"
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

CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
COMMIT_SHA="$(cd "$REPO_ROOT" && git rev-parse "$COMMIT")"
COMMIT_SHORT="${COMMIT_SHA:0:8}"

echo "Running perf test at commit $COMMIT_SHORT ($COMMIT_SHA)"

# Create worktree
WORKTREE_DIR="$(mktemp -d)"
cleanup() {
    cd "$REPO_ROOT"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
}
trap cleanup EXIT

cd "$REPO_ROOT"
git worktree add "$WORKTREE_DIR" "$COMMIT_SHA" --detach --quiet

WC="$WORKTREE_DIR/csharp"

echo "Building..."
docker build --target perf -t "bq-perf-$COMMIT_SHORT" -f "$WC/Dockerfile" "$WC" --quiet

echo "Running perf test..."
env_args=()
if [[ -f "$ENV_FILE" ]]; then
    env_args+=(--env-file "$ENV_FILE")
fi

OUTPUT=$(docker run --rm \
    "${env_args[@]}" \
    -e "BIGQUERY_PERF_CONFIG_FILE=/app/perfconfig.json" \
    -v "$CONFIG_FILE:/app/perfconfig.json:ro" \
    "bq-perf-$COMMIT_SHORT" \
    dotnet test /app/perf/ \
        --no-build \
        --logger "console;verbosity=detailed" \
        --filter "FullyQualifiedName~MeasureFullTableImport" \
    2>&1) || true

echo "$OUTPUT"

# Clean up image
docker rmi "bq-perf-$COMMIT_SHORT" --quiet 2>/dev/null || true

# Optionally append to PERFTESTS.md
if [[ -n "$APPEND_TO" ]]; then
    {
        echo ""
        echo "### Ad-hoc run: commit \`$COMMIT_SHORT\`"
        echo ""
        echo "**Full SHA:** \`$COMMIT_SHA\`"
        echo "**Date:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo ""
        echo "<details>"
        echo "<summary>Full output</summary>"
        echo ""
        echo '```'
        echo "$OUTPUT"
        echo '```'
        echo "</details>"
        echo ""
    } >> "$APPEND_TO"
    echo "Results appended to $APPEND_TO"
fi
