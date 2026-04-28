#!/usr/bin/env bash
#
# run-perf-suite.sh — Stacked patch performance test orchestrator
#
# Runs the BigQuery ADBC C# performance tests with patches applied
# incrementally. Each test level stacks one more patch on top of
# the previous, measuring cumulative impact.
#
# Results are written to PERFTESTS.md with both a summary table
# and detailed per-test sections.
#
# Usage:
#   ./scripts/run-perf-suite.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to perfconfig.json (required)
#   --commit SHA        Git commit to test against (default: HEAD)
#   --patches DIR       Directory containing .patch files (default: ./patches)
#   --output PATH       Output file path (default: ./PERFTESTS.md)
#   --skip-baseline     Skip the baseline (no-patches) run
#   --only N            Only run up to patch N (0 = baseline only)
#   --env-file PATH     Path to .env file for Docker (default: ./.env)
#   --help              Show this help message
#
set -euo pipefail

# ----- defaults -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSHARP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$CSHARP_DIR/.." && pwd)"

CONFIG_FILE=""
COMMIT="HEAD"
PATCHES_DIR="$CSHARP_DIR/patches"
OUTPUT_FILE="$CSHARP_DIR/PERFTESTS.md"
SKIP_BASELINE=false
ONLY_UPTO=-1  # -1 means all
ENV_FILE="$CSHARP_DIR/.env"

# ----- parse args -----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     CONFIG_FILE="$2"; shift 2 ;;
        --commit)     COMMIT="$2"; shift 2 ;;
        --patches)    PATCHES_DIR="$2"; shift 2 ;;
        --output)     OUTPUT_FILE="$2"; shift 2 ;;
        --skip-baseline) SKIP_BASELINE=true; shift ;;
        --only)       ONLY_UPTO="$2"; shift 2 ;;
        --env-file)   ENV_FILE="$2"; shift 2 ;;
        --help)
            head -28 "$0" | tail -22
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: --config is required (path to perfconfig.json)" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Resolve to absolute paths
CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"

# ----- discover patches -----
PATCH_FILES=()
if [[ -d "$PATCHES_DIR" ]]; then
    while IFS= read -r f; do
        PATCH_FILES+=("$f")
    done < <(find "$PATCHES_DIR" -name '*.patch' -type f | sort)
fi

TOTAL_PATCHES=${#PATCH_FILES[@]}
echo "Found $TOTAL_PATCHES patches in $PATCHES_DIR"

if [[ "$ONLY_UPTO" -ge 0 ]] && [[ "$ONLY_UPTO" -lt "$TOTAL_PATCHES" ]]; then
    TOTAL_PATCHES=$ONLY_UPTO
fi

# ----- resolve commit -----
COMMIT_SHA="$(cd "$REPO_ROOT" && git rev-parse "$COMMIT")"
COMMIT_SHORT="${COMMIT_SHA:0:8}"
echo "Testing against commit: $COMMIT_SHA"

# ----- create worktree -----
WORKTREE_DIR="$(mktemp -d)"
WORKTREE_NAME="perf-test-$$"
echo "Creating worktree at $WORKTREE_DIR ..."

cleanup() {
    echo ""
    echo "Cleaning up worktree..."
    cd "$REPO_ROOT"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    echo "Done."
}
trap cleanup EXIT

cd "$REPO_ROOT"
git worktree add "$WORKTREE_DIR" "$COMMIT_SHA" --detach --quiet
echo "Worktree created."

# ----- helper: run one perf test -----
RESULTS_DIR="$(mktemp -d)"
TEST_NUM=0

run_perf_test() {
    local label="$1"
    local test_id="$2"

    echo ""
    echo "=========================================="
    echo "Running: $label"
    echo "=========================================="

    local wt_csharp="$WORKTREE_DIR/csharp"

    # Build the perf test image
    echo "  Building Docker image..."
    if ! docker build \
        --target perf \
        -t "bq-perf-$test_id" \
        -f "$wt_csharp/Dockerfile" \
        "$wt_csharp" \
        --quiet 2>"$RESULTS_DIR/${test_id}_build.log"; then

        echo "  ❌ Build FAILED for $label"
        echo "BUILD_FAILED" > "$RESULTS_DIR/${test_id}_status"
        cat "$RESULTS_DIR/${test_id}_build.log"
        return 1
    fi

    echo "  Build succeeded. Running perf test..."

    # Prepare env args
    local env_args=()
    if [[ -f "$ENV_FILE" ]]; then
        env_args+=(--env-file "$ENV_FILE")
    fi

    # Run the perf test
    local output_file="$RESULTS_DIR/${test_id}_output.txt"
    local start_time end_time

    start_time=$(date +%s)

    if docker run --rm \
        "${env_args[@]}" \
        -e "BIGQUERY_PERF_CONFIG_FILE=/app/perfconfig.json" \
        -v "$CONFIG_FILE:/app/perfconfig.json:ro" \
        "bq-perf-$test_id" \
        dotnet test /app/perf/ \
            --no-build \
            --logger "console;verbosity=detailed" \
            --filter "FullyQualifiedName~MeasureFullTableImport" \
        > "$output_file" 2>&1; then

        end_time=$(date +%s)
        echo "  ✅ Test passed ($((end_time - start_time))s)"
        echo "PASSED" > "$RESULTS_DIR/${test_id}_status"
    else
        end_time=$(date +%s)
        echo "  ❌ Test FAILED ($((end_time - start_time))s)"
        echo "FAILED" > "$RESULTS_DIR/${test_id}_status"
    fi

    echo "$((end_time - start_time))" > "$RESULTS_DIR/${test_id}_wallclock"

    # Clean up docker image
    docker rmi "bq-perf-$test_id" --quiet 2>/dev/null || true
}

# ----- extract metrics from test output -----
extract_metric() {
    local file="$1"
    local pattern="$2"
    grep -oE "$pattern[^|]*" "$file" 2>/dev/null | head -1 | sed "s/$pattern//" | xargs || echo "N/A"
}

parse_test_output() {
    local test_id="$1"
    local output_file="$RESULTS_DIR/${test_id}_output.txt"

    if [[ ! -f "$output_file" ]]; then
        echo "N/A|N/A|N/A|N/A|N/A|N/A"
        return
    fi

    # Parse key metrics from the dotnet test console output
    local total_rows total_batches total_time throughput_rows throughput_bytes
    total_rows=$(grep -oP 'Total rows:\s*\K[\d,]+' "$output_file" 2>/dev/null | head -1 | tr -d ',' || echo "N/A")
    total_batches=$(grep -oP 'Total batches:\s*\K[\d,]+' "$output_file" 2>/dev/null | head -1 | tr -d ',' || echo "N/A")
    total_time=$(grep -oP 'Total time:\s*\K[\d.]+' "$output_file" 2>/dev/null | head -1 || echo "N/A")
    throughput_rows=$(grep -oP 'Throughput:\s*\K[\d,.]+\s*rows/sec' "$output_file" 2>/dev/null | head -1 || echo "N/A")
    throughput_bytes=$(grep -oP 'Throughput:\s*[\d,.]+\s*rows/sec,\s*\K[\d,.]+\s*[KMGT]?B/sec' "$output_file" 2>/dev/null | head -1 || echo "N/A")

    # Also try to extract from the ITestOutputHelper standard messages
    if [[ "$total_rows" == "N/A" ]]; then
        total_rows=$(grep -oP 'rows:\s*\K[\d,]+' "$output_file" 2>/dev/null | head -1 | tr -d ',' || echo "N/A")
    fi
    if [[ "$total_time" == "N/A" ]]; then
        total_time=$(grep -oP '[Tt]otal.*?:\s*\K[\d.]+\s*s' "$output_file" 2>/dev/null | head -1 || echo "N/A")
    fi

    echo "${total_rows}|${total_batches}|${total_time}|${throughput_rows}|${throughput_bytes}"
}

# ----- run baseline -----
if [[ "$SKIP_BASELINE" == false ]]; then
    run_perf_test "Baseline (no patches) @ $COMMIT_SHORT" "baseline"
fi

# ----- run stacked patches -----
for ((i = 0; i < TOTAL_PATCHES; i++)); do
    patch_file="${PATCH_FILES[$i]}"
    patch_name="$(basename "$patch_file" .patch)"

    echo ""
    echo "Applying patch $((i+1))/$TOTAL_PATCHES: $patch_name"

    # Apply patch to worktree
    cd "$WORKTREE_DIR"
    if ! git apply --check "$patch_file" 2>/dev/null; then
        echo "  ⚠️  Patch does not apply cleanly with git apply, trying with --3way..."
        if ! git apply --3way "$patch_file" 2>/dev/null; then
            echo "  ⚠️  --3way failed, trying fuzzy apply..."
            if ! patch -p1 --fuzz=3 < "$patch_file" 2>/dev/null; then
                echo "  ❌ Patch $patch_name FAILED to apply. Skipping."
                echo "PATCH_FAILED" > "$RESULTS_DIR/patch$(printf '%02d' $((i+1)))_status"
                continue
            fi
        fi
    else
        git apply "$patch_file"
    fi

    echo "  Patch applied."

    run_perf_test "Patch $((i+1)): $patch_name (cumulative) @ $COMMIT_SHORT" "patch$(printf '%02d' $((i+1)))"
done

# ----- generate PERFTESTS.md -----
echo ""
echo "=========================================="
echo "Generating $OUTPUT_FILE"
echo "=========================================="

{
    echo "# Performance Test Results"
    echo ""
    echo "**Commit:** \`$COMMIT_SHA\`"
    echo "**Date:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "**Patches:** $TOTAL_PATCHES applied incrementally"
    echo ""

    # Summary table
    echo "## Summary"
    echo ""
    echo "| # | Configuration | Status | Total Rows | Total Batches | Total Time | Throughput (rows/s) | Throughput (bytes/s) |"
    echo "|---|--------------|--------|-----------|--------------|------------|--------------------|--------------------|"

    # Baseline row
    if [[ "$SKIP_BASELINE" == false ]]; then
        status=$(cat "$RESULTS_DIR/baseline_status" 2>/dev/null || echo "SKIPPED")
        if [[ "$status" == "PASSED" ]]; then
            metrics=$(parse_test_output "baseline")
            IFS='|' read -r rows batches time thr_rows thr_bytes <<< "$metrics"
            echo "| 0 | Baseline (no patches) | ✅ $status | $rows | $batches | $time | $thr_rows | $thr_bytes |"
        else
            echo "| 0 | Baseline (no patches) | ❌ $status | - | - | - | - | - |"
        fi
    fi

    # Patch rows
    for ((i = 0; i < TOTAL_PATCHES; i++)); do
        test_id="patch$(printf '%02d' $((i+1)))"
        patch_name="$(basename "${PATCH_FILES[$i]}" .patch)"
        status=$(cat "$RESULTS_DIR/${test_id}_status" 2>/dev/null || echo "SKIPPED")

        if [[ "$status" == "PASSED" ]]; then
            metrics=$(parse_test_output "$test_id")
            IFS='|' read -r rows batches time thr_rows thr_bytes <<< "$metrics"
            echo "| $((i+1)) | +$patch_name | ✅ $status | $rows | $batches | $time | $thr_rows | $thr_bytes |"
        else
            echo "| $((i+1)) | +$patch_name | ❌ $status | - | - | - | - | - |"
        fi
    done

    echo ""

    # Detailed sections
    echo "## Detailed Results"
    echo ""

    if [[ "$SKIP_BASELINE" == false ]] && [[ -f "$RESULTS_DIR/baseline_output.txt" ]]; then
        echo "### Baseline (no patches)"
        echo ""
        echo "**Wall-clock time:** $(cat "$RESULTS_DIR/baseline_wallclock" 2>/dev/null || echo "N/A")s (including Docker build)"
        echo ""
        echo "<details>"
        echo "<summary>Full test output</summary>"
        echo ""
        echo '```'
        cat "$RESULTS_DIR/baseline_output.txt" 2>/dev/null || echo "(no output)"
        echo '```'
        echo "</details>"
        echo ""
    fi

    for ((i = 0; i < TOTAL_PATCHES; i++)); do
        test_id="patch$(printf '%02d' $((i+1)))"
        patch_name="$(basename "${PATCH_FILES[$i]}" .patch)"

        echo "### Patch $((i+1)): $patch_name"
        echo ""
        echo "**Cumulative patches applied:** $(seq -s ", " 1 $((i+1)) | sed 's/[0-9]*/P&/g')"
        echo "**Wall-clock time:** $(cat "$RESULTS_DIR/${test_id}_wallclock" 2>/dev/null || echo "N/A")s"
        echo ""

        if [[ -f "$RESULTS_DIR/${test_id}_output.txt" ]]; then
            echo "<details>"
            echo "<summary>Full test output</summary>"
            echo ""
            echo '```'
            cat "$RESULTS_DIR/${test_id}_output.txt"
            echo '```'
            echo "</details>"
        else
            echo "*No output available.*"
        fi
        echo ""
    done

    echo "---"
    echo "*Generated by \`run-perf-suite.sh\` on $(date -u '+%Y-%m-%d %H:%M:%S UTC')*"

} > "$OUTPUT_FILE"

echo "Results written to $OUTPUT_FILE"
echo ""
echo "Done! 🎉"
