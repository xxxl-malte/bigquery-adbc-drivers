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
#   --image NAME        Docker SDK image (default: mcr.microsoft.com/dotnet/sdk:8.0)
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
DOCKER_IMAGE="mcr.microsoft.com/dotnet/sdk:8.0"

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
        --image)      DOCKER_IMAGE="$2"; shift 2 ;;
        --help)
            head -30 "$0" | tail -24
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

# ----- pull Docker image -----
echo "Pulling Docker image: $DOCKER_IMAGE ..."
docker pull "$DOCKER_IMAGE" --quiet >/dev/null 2>&1 || true

# ----- create worktree -----
WORKTREE_DIR="$(mktemp -d)"
echo "Creating worktree at $WORKTREE_DIR ..."

cleanup() {
    echo ""
    echo "Cleaning up worktree..."
    cd "$REPO_ROOT"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    if [[ -n "${RESULTS_DIR:-}" ]] && [[ -d "$RESULTS_DIR" ]]; then
        rm -rf "$RESULTS_DIR"
    fi
    echo "Done."
}
trap cleanup EXIT

cd "$REPO_ROOT"
git worktree add "$WORKTREE_DIR" "$COMMIT_SHA" --detach --quiet
echo "Worktree created."

# ----- initialize submodule in worktree -----
# Git worktrees don't auto-init submodules; the csharp/arrow-adbc
# directory will be empty. We copy it from the main tree to avoid
# a slow re-clone from GitHub.
WT_CSHARP="$WORKTREE_DIR/csharp"
MAIN_SUBMODULE="$CSHARP_DIR/arrow-adbc"

if [[ -d "$MAIN_SUBMODULE/.git" ]] || [[ -f "$MAIN_SUBMODULE/.git" ]]; then
    echo "Copying submodule arrow-adbc into worktree..."
    rm -rf "$WT_CSHARP/arrow-adbc"
    cp -R "$MAIN_SUBMODULE" "$WT_CSHARP/arrow-adbc"
    echo "  Submodule copied."
else
    echo "Initializing submodule in worktree (may take a minute)..."
    cd "$WORKTREE_DIR"
    git submodule update --init --recursive
    echo "  Submodule initialized."
fi

# ----- copy test infrastructure into worktree -----
# The perf/ directory may not exist at the target commit (it was added
# later). Copy it from the current tree so the worktree can run
# performance tests at any commit.
echo "Copying test infrastructure into worktree..."
rm -rf "$WT_CSHARP/perf"
cp -R "$CSHARP_DIR/perf" "$WT_CSHARP/perf"
echo "  Copied: perf/"

# ----- helper: run one perf test -----
RESULTS_DIR="$(mktemp -d)"

run_perf_test() {
    local label="$1"
    local test_id="$2"

    echo ""
    echo "=========================================="
    echo "Running: $label"
    echo "=========================================="

    local wt_csharp="$WORKTREE_DIR/csharp"
    local output_file="$RESULTS_DIR/${test_id}_output.txt"

    # Clean previous build artifacts (src + perf only, NOT arrow-adbc)
    # This ensures patches get a fresh build instead of stale incremental results
    echo "  Cleaning build artifacts..."
    rm -rf "$wt_csharp/src/obj" "$wt_csharp/src/bin"
    rm -rf "$wt_csharp/perf/obj" "$wt_csharp/perf/bin"
    rm -rf "$wt_csharp/artifacts/AdbcDrivers.BigQuery"
    rm -rf "$wt_csharp/artifacts/AdbcDrivers.BigQuery.Perf"

    # Prepare volume mounts and env args
    local env_args=()
    if [[ -f "$ENV_FILE" ]]; then
        env_args+=(--env-file "$ENV_FILE")
    fi

    # Mount GCP credentials if available (for Application Default Credentials)
    local gcp_cred_args=()
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] && [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        gcp_cred_args+=(-v "$GOOGLE_APPLICATION_CREDENTIALS:/repo/gcp-credentials.json:ro")
        gcp_cred_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
    elif [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
        gcp_cred_args+=(-v "$HOME/.config/gcloud/application_default_credentials.json:/repo/gcp-credentials.json:ro")
        gcp_cred_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
    fi

    # Run build + test in a single docker invocation
    # (no --no-build: ensures dotnet test knows the correct output path)
    echo "  Building & running perf test..."
    local start_time end_time
    start_time=$(date +%s)

    if docker run --rm \
        ${env_args[@]+"${env_args[@]}"} \
        ${gcp_cred_args[@]+"${gcp_cred_args[@]}"} \
        -v nuget-perf-cache:/root/.nuget/packages \
        -e "BIGQUERY_PERF_CONFIG_FILE=/repo/perfconfig.json" \
        -v "$wt_csharp:/repo/csharp" \
        -v "$CONFIG_FILE:/repo/perfconfig.json:ro" \
        -w /repo/csharp \
        "$DOCKER_IMAGE" \
        dotnet test perf/AdbcDrivers.BigQuery.Perf.csproj \
            -c Release \
            --logger "console;verbosity=detailed" \
            --filter "FullyQualifiedName=AdbcDrivers.BigQuery.Perf.FullTableImportTest.MeasureFullTableImport" \
        > "$output_file" 2>&1; then

        end_time=$(date +%s)

        # Verify tests actually ran (exit 0 with 0 tests = nothing executed)
        if grep -qE "Total tests:.*0[^0-9]" "$output_file" 2>/dev/null && \
           ! grep -qE "Passed:[[:space:]]*[1-9]" "$output_file" 2>/dev/null; then
            echo "  ⚠️  No tests executed (exit 0 but 0 tests passed)"
            echo "NO_TESTS" > "$RESULTS_DIR/${test_id}_status"
        elif grep -qE "Skipped:[[:space:]]*[1-9]" "$output_file" 2>/dev/null && \
             ! grep -qE "Passed:[[:space:]]*[1-9]" "$output_file" 2>/dev/null; then
            echo "  ⚠️  Test skipped (missing credentials or config)"
            echo "SKIPPED" > "$RESULTS_DIR/${test_id}_status"
        else
            echo "  ✅ Test passed ($((end_time - start_time))s)"
            echo "PASSED" > "$RESULTS_DIR/${test_id}_status"
        fi
    else
        end_time=$(date +%s)

        # Distinguish build failure from test failure
        if grep -qE "Build FAILED|Error\(s\)" "$output_file" 2>/dev/null && \
           ! grep -qE "Total tests:" "$output_file" 2>/dev/null; then
            echo "  ❌ Build FAILED for $label"
            echo "BUILD_FAILED" > "$RESULTS_DIR/${test_id}_status"
            echo ""
            tail -20 "$output_file"
        else
            echo "  ❌ Test FAILED ($((end_time - start_time))s)"
            echo "FAILED" > "$RESULTS_DIR/${test_id}_status"
        fi
    fi

    echo "$((end_time - start_time))" > "$RESULTS_DIR/${test_id}_wallclock"
}

# ----- extract metrics from test output -----
parse_test_output() {
    local test_id="$1"
    local output_file="$RESULTS_DIR/${test_id}_output.txt"

    if [[ ! -f "$output_file" ]]; then
        echo "N/A|N/A|N/A|N/A|N/A"
        return
    fi

    # Parse metrics from the test's ITestOutputHelper output
    # Format: "  Total rows:       25,034,075"
    local total_rows total_batches total_time throughput_rows throughput_bytes

    total_rows=$(sed -n 's/.*Total rows:[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" | head -1)
    total_batches=$(sed -n 's/.*Total batches:[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" | head -1)
    # Total time is in TimeSpan format: "00:47:25.3457848"
    total_time=$(sed -n 's/.*Total:[[:space:]]*\([0-9.:]*\).*/\1/p' "$output_file" | head -1)
    # Rows/sec (read): 8,812
    throughput_rows=$(sed -n 's/.*Rows\/sec (read):[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" | head -1)
    # Bytes/sec (read): 1,381,763 (1.32 MB/s)
    throughput_bytes=$(sed -n 's/.*Bytes\/sec (read):[[:space:]]*[0-9,]* (\([^)]*\)).*/\1/p' "$output_file" | head -1)

    echo "${total_rows:-N/A}|${total_batches:-N/A}|${total_time:-N/A}|${throughput_rows:-N/A}|${throughput_bytes:-N/A}"
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
        if ! git apply "$patch_file"; then
            echo "  ❌ Patch $patch_name FAILED to apply (apply after successful check). Skipping."
            echo "PATCH_FAILED" > "$RESULTS_DIR/patch$(printf '%02d' $((i+1)))_status"
            continue
        fi
    fi

    echo "  Patch applied."

    run_perf_test "Patch $((i+1)): $patch_name (cumulative) @ $COMMIT_SHORT" "patch$(printf '%02d' $((i+1)))"
done

# ----- generate PERFTESTS.md -----
echo ""
echo "=========================================="
echo "Generating $OUTPUT_FILE"
echo "=========================================="

# Helper: choose emoji based on status
status_emoji() {
    case "$1" in
        PASSED)       echo "✅" ;;
        SKIPPED|NO_TESTS) echo "⚠️" ;;
        *)            echo "❌" ;;
    esac
}

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
        emoji=$(status_emoji "$status")
        if [[ "$status" == "PASSED" ]]; then
            metrics=$(parse_test_output "baseline")
            IFS='|' read -r rows batches time thr_rows thr_bytes <<< "$metrics"
            echo "| 0 | Baseline (no patches) | $emoji $status | $rows | $batches | $time | $thr_rows | $thr_bytes |"
        else
            echo "| 0 | Baseline (no patches) | $emoji $status | - | - | - | - | - |"
        fi
    fi

    # Patch rows
    for ((i = 0; i < TOTAL_PATCHES; i++)); do
        test_id="patch$(printf '%02d' $((i+1)))"
        patch_name="$(basename "${PATCH_FILES[$i]}" .patch)"
        status=$(cat "$RESULTS_DIR/${test_id}_status" 2>/dev/null || echo "SKIPPED")
        emoji=$(status_emoji "$status")

        if [[ "$status" == "PASSED" ]]; then
            metrics=$(parse_test_output "$test_id")
            IFS='|' read -r rows batches time thr_rows thr_bytes <<< "$metrics"
            echo "| $((i+1)) | +$patch_name | $emoji $status | $rows | $batches | $time | $thr_rows | $thr_bytes |"
        else
            echo "| $((i+1)) | +$patch_name | $emoji $status | - | - | - | - | - |"
        fi
    done

    echo ""

    # Detailed sections
    echo "## Detailed Results"
    echo ""

    if [[ "$SKIP_BASELINE" == false ]] && [[ -f "$RESULTS_DIR/baseline_output.txt" ]]; then
        echo "### Baseline (no patches)"
        echo ""
        echo "**Wall-clock time:** $(cat "$RESULTS_DIR/baseline_wallclock" 2>/dev/null || echo "N/A")s"
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
        echo "**Cumulative patches applied:** $(seq 1 $((i+1)) | while read n; do printf "P%s" "$n"; done | sed 's/P/, P/g; s/^, //')"
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
