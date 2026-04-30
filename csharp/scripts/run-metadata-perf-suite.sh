#!/usr/bin/env bash
#
# run-metadata-perf-suite.sh — Stacked patch performance suite for the
# metadata path (Connection.GetObjects).
#
# Mirrors run-perf-suite.sh but exercises the schema-discovery path
# instead of full-table-import. Use this script to evaluate patches that
# touch INFORMATION_SCHEMA queries, GetObjects fan-out, parameterized
# metadata queries, and streaming GetObjects (e.g. patches 01, 02, 08,
# 09, 10, 13 in the current series). The data-path test in
# run-perf-suite.sh does not exercise those code paths.
#
# Results are written to PERFTESTS_METADATA.md (default).
#
# Usage:
#   ./scripts/run-metadata-perf-suite.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to perfconfig.json (required)
#   --commit SHA        Git commit to test against (default: HEAD)
#   --patches DIR       Directory containing .patch files (default: ./patches)
#   --output PATH       Output file path (default: ./PERFTESTS_METADATA.md)
#   --skip-baseline     Skip the baseline (no-patches) run
#   --only N            Only run up to patch N (0 = baseline only)
#   --env-file PATH     Path to .env file for Docker (default: ./.env)
#   --image NAME        Docker SDK image (default: mcr.microsoft.com/dotnet/sdk:8.0)
#   --cooldown SECS     Seconds to wait between test runs (default: 30)
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
OUTPUT_FILE="$CSHARP_DIR/PERFTESTS_METADATA.md"
SKIP_BASELINE=false
ONLY_UPTO=-1  # -1 means all
ENV_FILE="$CSHARP_DIR/.env"
DOCKER_IMAGE="mcr.microsoft.com/dotnet/sdk:8.0"
# Metadata calls don't go through the Storage Read API, so server-side
# throttling is far less of a concern than for the data path. Default
# cooldown is correspondingly shorter than run-perf-suite.sh.
COOLDOWN_SECS=30

# Patches whose effects live on the data path (Storage Read API, query
# execution, gRPC channels). They are still applied (so the canonical
# 1→16 stack is preserved for tested rows), but their per-patch
# build+test is skipped — this script's metadata test would not measure
# their effect anyway. Use run-perf-suite.sh to evaluate these patches.
# Patch numbers are matched by the leading two-digit prefix of the patch
# filename (e.g. "06-reuse-..." → "06").
SKIP_TEST_PATCHES=(06 07 11 12 15 16)

# Test filters (the only meaningful difference from run-perf-suite.sh besides
# the parsed metrics). Kept as variables so the rest of the script reads
# identically to its sibling.
TEST_FILTER="FullyQualifiedName=AdbcDrivers.BigQuery.Perf.GetObjectsTest.MeasureGetObjectsRepeated"
PREFLIGHT_FILTER="FullyQualifiedName=AdbcDrivers.BigQuery.Perf.GetObjectsTest.VerifyMetadataConnectivity"

# Track suite state
SUITE_START_TIME="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
SUITE_COMPLETED=false

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
        --cooldown)   COOLDOWN_SECS="$2"; shift 2 ;;
        --help)
            head -31 "$0" | tail -25
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

# ----- ensure nuget cache volume is writable by host user -----
# Docker named volumes default to root:root ownership. The build/test
# containers below run with --user "$(id -u):$(id -g)" so artifacts land
# with host ownership; without this chown they can't write to the cache
# and dotnet restore fails with "Access to the path '/tmp/nuget-cache'
# is denied". This container intentionally omits --user so it runs as
# root and can chown the volume. Idempotent: a no-op once ownership is
# correct.
echo "Ensuring NuGet cache volume ownership..."
docker volume create nuget-perf-cache >/dev/null
docker run --rm -v nuget-perf-cache:/cache "$DOCKER_IMAGE" \
    chown -R "$(id -u):$(id -g)" /cache

# ----- create worktree -----
WORKTREE_DIR="$(mktemp -d)"
echo "Creating worktree at $WORKTREE_DIR ..."

cleanup() {
    echo ""
    if [[ "$SUITE_COMPLETED" == false ]] && [[ -n "${RESULTS_DIR:-}" ]] && [[ -d "$RESULTS_DIR" ]]; then
        write_perftests_md || true
        echo "Results saved to $OUTPUT_FILE"
    fi
    rm -f "${OUTPUT_FILE}.tmp."* 2>/dev/null || true
    echo "Cleaning up worktree..."
    if [[ -d "$WORKTREE_DIR" ]]; then
        docker run --rm -v "$WORKTREE_DIR:/worktree" "$DOCKER_IMAGE" \
            chown -R "$(id -u):$(id -g)" /worktree 2>/dev/null || true
    fi
    cd "$REPO_ROOT"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    if [[ -n "${RESULTS_DIR:-}" ]] && [[ -d "$RESULTS_DIR" ]]; then
        rm -rf "$RESULTS_DIR"
    fi
    echo "Done."
}
trap cleanup EXIT
trap 'echo ""; echo "Interrupted — stopping suite..."; exit 130' INT

cd "$REPO_ROOT"
git worktree add "$WORKTREE_DIR" "$COMMIT_SHA" --detach --quiet
echo "Worktree created."

# ----- initialize submodule in worktree -----
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
# later). Copy it from the current tree so the worktree can run the
# metadata tests at any commit.
echo "Copying test infrastructure into worktree..."
rm -rf "$WT_CSHARP/perf"
cp -R "$CSHARP_DIR/perf" "$WT_CSHARP/perf"
echo "  Copied: perf/"

# ----- purge host build artifacts from worktree -----
echo "Cleaning host build artifacts from worktree..."
find "$WT_CSHARP" -type d \( -name obj -o -name bin \) -exec rm -rf {} + 2>/dev/null || true
echo "  Done."

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

    echo "  Cleaning build artifacts..."
    rm -rf "$wt_csharp/src/obj" "$wt_csharp/src/bin"
    rm -rf "$wt_csharp/perf/bin"
    rm -rf "$wt_csharp/artifacts/AdbcDrivers.BigQuery"
    rm -rf "$wt_csharp/artifacts/AdbcDrivers.BigQuery.Perf"

    local env_args=()
    if [[ -f "$ENV_FILE" ]]; then
        env_args+=(--env-file "$ENV_FILE")
    fi

    local gcp_cred_args=()
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] && [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        gcp_cred_args+=(-v "$GOOGLE_APPLICATION_CREDENTIALS:/repo/gcp-credentials.json:ro")
        gcp_cred_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
    elif [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
        gcp_cred_args+=(-v "$HOME/.config/gcloud/application_default_credentials.json:/repo/gcp-credentials.json:ro")
        gcp_cred_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
    fi

    local -a docker_common=(
        --rm
        --user "$(id -u):$(id -g)"
        -e HOME=/tmp/dotnet-home
        -e DOTNET_CLI_HOME=/tmp/dotnet-home
        -e NUGET_PACKAGES=/tmp/nuget-cache
        ${env_args[@]+"${env_args[@]}"}
        ${gcp_cred_args[@]+"${gcp_cred_args[@]}"}
        -v nuget-perf-cache:/tmp/nuget-cache
        -v "$wt_csharp:/repo/csharp"
        -w /repo/csharp
    )

    # --- Step 1: Build (NOT counted towards performance measurement) ---
    echo "  Building..."
    local build_start build_end build_file="$RESULTS_DIR/${test_id}_build.txt"
    build_start=$(date +%s)

    if ! docker run "${docker_common[@]}" \
        "$DOCKER_IMAGE" \
        sh -c "dotnet restore perf/AdbcDrivers.BigQuery.Perf.csproj && dotnet build perf/AdbcDrivers.BigQuery.Perf.csproj -c Release --no-restore" \
        > "$build_file" 2>&1; then

        build_end=$(date +%s)
        echo "  ❌ Build FAILED ($((build_end - build_start))s)"
        echo "BUILD_FAILED" > "$RESULTS_DIR/${test_id}_status"
        echo "$((build_end - build_start))" > "$RESULTS_DIR/${test_id}_buildtime"
        echo "0" > "$RESULTS_DIR/${test_id}_wallclock"
        date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/${test_id}_completed"
        cp "$build_file" "$output_file"
        echo ""
        tail -20 "$output_file"
        return
    fi

    build_end=$(date +%s)
    local build_secs=$((build_end - build_start))
    echo "$build_secs" > "$RESULTS_DIR/${test_id}_buildtime"
    echo "  Build succeeded (${build_secs}s)"

    # --- Step 2: Run test only (this is the timed performance measurement) ---
    echo "  Running metadata perf test..."
    local start_time end_time
    start_time=$(date +%s)

    if docker run "${docker_common[@]}" \
        -e "BIGQUERY_PERF_CONFIG_FILE=/repo/perfconfig.json" \
        -v "$CONFIG_FILE:/repo/perfconfig.json:ro" \
        "$DOCKER_IMAGE" \
        dotnet test perf/AdbcDrivers.BigQuery.Perf.csproj \
            -c Release \
            --no-build \
            --logger "console;verbosity=detailed" \
            --filter "$TEST_FILTER" \
        > "$output_file" 2>&1; then

        end_time=$(date +%s)

        if grep -qE "Total tests:.*0[^0-9]" "$output_file" 2>/dev/null && \
           ! grep -qE "Passed:[[:space:]]*[1-9]" "$output_file" 2>/dev/null; then
            echo "  ⚠️  No tests executed (exit 0 but 0 tests passed)"
            echo "NO_TESTS" > "$RESULTS_DIR/${test_id}_status"
        elif grep -qE "Skipped:[[:space:]]*[1-9]" "$output_file" 2>/dev/null && \
             ! grep -qE "Passed:[[:space:]]*[1-9]" "$output_file" 2>/dev/null; then
            echo "  ⚠️  Test skipped (missing credentials or config)"
            echo "SKIPPED" > "$RESULTS_DIR/${test_id}_status"
        else
            echo "  ✅ Test passed (build: ${build_secs}s, test: $((end_time - start_time))s)"
            echo "PASSED" > "$RESULTS_DIR/${test_id}_status"
        fi
    else
        end_time=$(date +%s)
        echo "  ❌ Test FAILED (build: ${build_secs}s, test: $((end_time - start_time))s)"
        echo "FAILED" > "$RESULTS_DIR/${test_id}_status"
    fi

    echo "$((end_time - start_time))" > "$RESULTS_DIR/${test_id}_wallclock"
    date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/${test_id}_completed"
}

# ----- extract metadata-path metrics from test output -----
# The lines being scraped here are written by
# GetObjectsTest.MeasureGetObjectsRepeated. Keep these regexes in sync
# with the Log() calls in that test. Output (pipe-separated):
#   iters | catalogs (avg) | batches (avg) | avg_dur (s) | min_dur | max_dur | stddev | peak_ws
#
# Each extraction wraps `sed` in `{ ... || true; }` to swallow SIGPIPE
# when `head -1` closes the pipe. Without this, `set -o pipefail` would
# propagate the failure and `set -e` would abort write_perftests_md
# mid-write, truncating PERFTESTS_METADATA.md.
parse_test_output() {
    local test_id="$1"
    local output_file="$RESULTS_DIR/${test_id}_output.txt"

    if [[ ! -f "$output_file" ]]; then
        echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A"
        return
    fi

    local iters catalogs batches avg_dur min_dur max_dur stddev peak_ws

    iters=$({ sed -n 's/.*Iterations:[[:space:]]*\([0-9]*\).*/\1/p' "$output_file" || true; } | head -1)
    # "  Avg catalogs:  16" — printed with N0 (no decimals), no commas
    # by F0 format, but allow commas from any other formatter just in case.
    catalogs=$({ sed -n 's/.*Avg catalogs:[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" || true; } | head -1)
    batches=$({ sed -n 's/.*Avg batches:[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" || true; } | head -1)
    avg_dur=$({ sed -n 's/.*Avg duration:[[:space:]]*\([0-9.]*\)s.*/\1/p' "$output_file" || true; } | head -1)
    min_dur=$({ sed -n 's/.*Min duration:[[:space:]]*\([0-9.]*\)s.*/\1/p' "$output_file" || true; } | head -1)
    max_dur=$({ sed -n 's/.*Max duration:[[:space:]]*\([0-9.]*\)s.*/\1/p' "$output_file" || true; } | head -1)
    stddev=$({ sed -n 's/.*Std deviation:[[:space:]]*\([0-9.]*\)s.*/\1/p' "$output_file" || true; } | head -1)
    # "Peak working set: 234.56 MB"
    peak_ws=$({ sed -n 's/.*Peak working set:[[:space:]]*\([0-9.]*[[:space:]]*[KMGT]\?B\).*/\1/p' "$output_file" || true; } | head -1)

    # Single-iteration runs (shouldn't happen with the Repeated test but
    # be defensive) print no stddev — treat as 0 so compute_delta_pct
    # still works.
    : "${stddev:=0}"

    echo "${iters:-N/A}|${catalogs:-N/A}|${batches:-N/A}|${avg_dur:-N/A}|${min_dur:-N/A}|${max_dur:-N/A}|${stddev:-N/A}|${peak_ws:-N/A}"
}

# ----- helper: check skip-test list -----
# Patches whose number appears in SKIP_TEST_PATCHES are still applied
# (preserves the canonical stack) but get no build+test run. They
# show up as OTHER_PATH rows in the report.
is_skip_test_patch() {
    local num="$1"
    for skip in "${SKIP_TEST_PATCHES[@]}"; do
        [[ "$num" == "$skip" ]] && return 0
    done
    return 1
}

# ----- helper: format Δ vs baseline as percentage with combined stddev -----
# Inputs: baseline_avg, baseline_stddev, patch_avg, patch_stddev (all seconds).
# Output (stdout): "+5.2% ± 1.8%" / "-3.1% ± 0.9%" / "—" if any input is missing.
# Sign convention: positive percentage = improvement (patch is faster than
# baseline). Combined stddev is the L2-norm of the two stddevs as a
# percentage of the baseline mean — rough propagation of uncertainty,
# not a formal CI. Same implementation as run-perf-suite.sh.
compute_delta_pct() {
    local baseline_avg="$1"
    local baseline_stddev="${2:-0}"
    local patch_avg="$3"
    local patch_stddev="${4:-0}"

    if [[ -z "$baseline_avg" || "$baseline_avg" == "N/A" || "$baseline_avg" == "0" ]]; then
        echo "—"
        return
    fi
    if [[ -z "$patch_avg" || "$patch_avg" == "N/A" ]]; then
        echo "—"
        return
    fi

    awk -v ba="$baseline_avg" -v bs="$baseline_stddev" -v pa="$patch_avg" -v ps="$patch_stddev" '
        BEGIN {
            if (ba == 0) { print "—"; exit }
            delta = (ba - pa) / ba * 100.0
            stddev = sqrt(bs * bs + ps * ps) / ba * 100.0
            sign = (delta >= 0) ? "+" : ""
            printf "%s%.1f%% ± %.1f%%", sign, delta, stddev
        }'
}

# ----- helper: status emoji -----
status_emoji() {
    case "$1" in
        PASSED)            echo "✅" ;;
        PENDING)           echo "⏳" ;;
        OTHER_PATH)        echo "⏭️" ;;
        SKIPPED|NO_TESTS)  echo "⚠️" ;;
        *)                 echo "❌" ;;
    esac
}

# ----- helper: (re)generate PERFTESTS_METADATA.md from current results -----
write_perftests_md() {
    local tmp_file
    tmp_file="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"

    # Capture baseline avg/stddev once so every patch row can compute its
    # Δ vs baseline. If the baseline didn't run or failed, BASELINE_AVG
    # stays empty and compute_delta_pct returns "—" for every patch row.
    local BASELINE_AVG="" BASELINE_STDDEV=""
    if [[ "$SKIP_BASELINE" == false ]]; then
        local b_status
        b_status=$(cat "$RESULTS_DIR/baseline_status" 2>/dev/null || echo "")
        if [[ "$b_status" == "PASSED" ]]; then
            local b_metrics
            b_metrics=$(parse_test_output "baseline")
            IFS='|' read -r _ _ _ b_avg _ _ b_stddev _ <<< "$b_metrics"
            BASELINE_AVG="$b_avg"
            BASELINE_STDDEV="$b_stddev"
        fi
    fi

    {
        echo "# Metadata Performance Test Results"
        echo ""
        echo "**Commit:** \`$COMMIT_SHA\`"
        echo "**Suite started:** $SUITE_START_TIME"
        echo "**Last updated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "**Patches:** $TOTAL_PATCHES applied incrementally"
        echo "**Cooldown between runs:** ${COOLDOWN_SECS}s"
        echo "**Test:** \`GetObjectsTest.MeasureGetObjectsRepeated\` (depth=All, avg of N iterations per row)"

        local preflight_status preflight_completed
        preflight_status=$(cat "$RESULTS_DIR/preflight_status" 2>/dev/null || echo "")
        if [[ -n "$preflight_status" ]]; then
            preflight_completed=$(cat "$RESULTS_DIR/preflight_completed" 2>/dev/null || echo "")
            echo "**Connectivity check:** $(status_emoji "$preflight_status") $preflight_status ($preflight_completed)"
        fi

        echo ""

        # Summary table — parallel to run-perf-suite.sh's: Iters / Avg /
        # Stddev / Δ vs Baseline ± stddev. Metadata-specific columns are
        # Catalogs (workload size) and Peak WS (memory metric for patch
        # 10). Throughput / row-count not applicable here.
        echo "## Summary"
        echo ""
        echo "| # | Configuration | Status | Build (s) | Test (s) | Completed | Iters | Catalogs | Avg (s) | Stddev (s) | Δ vs Baseline ± stddev | Peak WS |"
        echo "|---|--------------|--------|----------|---------|-----------|-------|---------|--------|-----------|-----------------------|--------|"

        # Baseline row
        if [[ "$SKIP_BASELINE" == false ]]; then
            local status completed emoji metrics iters catalogs batches avg_dur min_dur max_dur stddev peak_ws
            local build_time test_time
            status=$(cat "$RESULTS_DIR/baseline_status" 2>/dev/null || echo "PENDING")
            completed=$(cat "$RESULTS_DIR/baseline_completed" 2>/dev/null || echo "-")
            build_time=$(cat "$RESULTS_DIR/baseline_buildtime" 2>/dev/null || echo "-")
            test_time=$(cat "$RESULTS_DIR/baseline_wallclock" 2>/dev/null || echo "-")
            emoji=$(status_emoji "$status")
            if [[ "$status" == "PASSED" ]]; then
                metrics=$(parse_test_output "baseline")
                IFS='|' read -r iters catalogs batches avg_dur min_dur max_dur stddev peak_ws <<< "$metrics"
                echo "| 0 | Baseline (no patches) | $emoji $status | $build_time | $test_time | $completed | $iters | $catalogs | $avg_dur | $stddev | — (reference) | $peak_ws |"
            else
                echo "| 0 | Baseline (no patches) | $emoji $status | $build_time | $test_time | $completed | - | - | - | - | - | - |"
            fi
        fi

        # Patch rows
        local pi test_id patch_name status completed emoji metrics iters catalogs batches avg_dur min_dur max_dur stddev peak_ws delta_str
        for ((pi = 0; pi < TOTAL_PATCHES; pi++)); do
            test_id="patch$(printf '%02d' $((pi+1)))"
            patch_name="$(basename "${PATCH_FILES[$pi]}" .patch)"
            status=$(cat "$RESULTS_DIR/${test_id}_status" 2>/dev/null || echo "PENDING")
            completed=$(cat "$RESULTS_DIR/${test_id}_completed" 2>/dev/null || echo "-")
            build_time=$(cat "$RESULTS_DIR/${test_id}_buildtime" 2>/dev/null || echo "-")
            test_time=$(cat "$RESULTS_DIR/${test_id}_wallclock" 2>/dev/null || echo "-")
            emoji=$(status_emoji "$status")

            if [[ "$status" == "PASSED" ]]; then
                metrics=$(parse_test_output "$test_id")
                IFS='|' read -r iters catalogs batches avg_dur min_dur max_dur stddev peak_ws <<< "$metrics"
                delta_str=$(compute_delta_pct "$BASELINE_AVG" "$BASELINE_STDDEV" "$avg_dur" "$stddev")
                echo "| $((pi+1)) | +$patch_name | $emoji $status | $build_time | $test_time | $completed | $iters | $catalogs | $avg_dur | $stddev | $delta_str | $peak_ws |"
            else
                echo "| $((pi+1)) | +$patch_name | $emoji $status | $build_time | $test_time | $completed | - | - | - | - | - | - |"
            fi
        done

        echo ""

        # Detailed sections
        echo "## Detailed Results"
        echo ""

        if [[ -f "$RESULTS_DIR/preflight_output.txt" ]]; then
            local pf_status pf_completed
            pf_status=$(cat "$RESULTS_DIR/preflight_status" 2>/dev/null || echo "N/A")
            pf_completed=$(cat "$RESULTS_DIR/preflight_completed" 2>/dev/null || echo "N/A")
            echo "### Preflight: Metadata Connectivity Check"
            echo ""
            echo "**Status:** $(status_emoji "$pf_status") $pf_status"
            echo "**Completed:** $pf_completed"
            echo ""
            echo "<details>"
            echo "<summary>Full preflight output</summary>"
            echo ""
            echo '```'
            cat "$RESULTS_DIR/preflight_output.txt"
            echo '```'
            echo "</details>"
            echo ""
        fi

        if [[ "$SKIP_BASELINE" == false ]] && [[ -f "$RESULTS_DIR/baseline_output.txt" ]]; then
            echo "### Baseline (no patches)"
            echo ""
            echo "**Completed:** $(cat "$RESULTS_DIR/baseline_completed" 2>/dev/null || echo "N/A")"
            echo "**Build time:** $(cat "$RESULTS_DIR/baseline_buildtime" 2>/dev/null || echo "N/A")s"
            echo "**Test time:** $(cat "$RESULTS_DIR/baseline_wallclock" 2>/dev/null || echo "N/A")s"
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

        for ((pi = 0; pi < TOTAL_PATCHES; pi++)); do
            test_id="patch$(printf '%02d' $((pi+1)))"
            patch_name="$(basename "${PATCH_FILES[$pi]}" .patch)"

            if [[ -f "$RESULTS_DIR/${test_id}_status" ]]; then
                echo "### Patch $((pi+1)): $patch_name"
                echo ""
                echo "**Cumulative patches:** 01 through $(printf '%02d' $((pi+1)))"
                echo "**Completed:** $(cat "$RESULTS_DIR/${test_id}_completed" 2>/dev/null || echo "N/A")"
                echo "**Build time:** $(cat "$RESULTS_DIR/${test_id}_buildtime" 2>/dev/null || echo "N/A")s"
                echo "**Test time:** $(cat "$RESULTS_DIR/${test_id}_wallclock" 2>/dev/null || echo "N/A")s"
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
            fi
        done

        echo "---"
        echo "*Generated by \`run-metadata-perf-suite.sh\` on $(date -u '+%Y-%m-%d %H:%M:%S UTC')*"

    } > "$tmp_file"

    mv -f "$tmp_file" "$OUTPUT_FILE"
}

# ----- helper: cooldown between test runs -----
cooldown_between_runs() {
    if [[ "$COOLDOWN_SECS" -le 0 ]]; then
        return
    fi
    echo ""
    echo "  ⏳ Cooldown: waiting ${COOLDOWN_SECS}s..."
    local remaining=$COOLDOWN_SECS
    while [[ $remaining -gt 0 ]]; do
        printf "\r  ⏳ Cooldown: %3ds remaining..." "$remaining"
        sleep 1
        remaining=$((remaining - 1))
    done
    printf "\r  ✅ Cooldown complete.                    \n"
}

# ----- preflight: verify metadata connectivity -----
echo ""
echo "=========================================="
echo "Preflight: Verifying metadata connectivity"
echo "=========================================="

preflight_env_args=()
if [[ -f "$ENV_FILE" ]]; then
    preflight_env_args+=(--env-file "$ENV_FILE")
fi

preflight_gcp_args=()
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] && [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    preflight_gcp_args+=(-v "$GOOGLE_APPLICATION_CREDENTIALS:/repo/gcp-credentials.json:ro")
    preflight_gcp_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
elif [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
    preflight_gcp_args+=(-v "$HOME/.config/gcloud/application_default_credentials.json:/repo/gcp-credentials.json:ro")
    preflight_gcp_args+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/repo/gcp-credentials.json")
fi

preflight_docker_common=(
    --rm
    --user "$(id -u):$(id -g)"
    -e HOME=/tmp/dotnet-home
    -e DOTNET_CLI_HOME=/tmp/dotnet-home
    -e NUGET_PACKAGES=/tmp/nuget-cache
    ${preflight_env_args[@]+"${preflight_env_args[@]}"}
    ${preflight_gcp_args[@]+"${preflight_gcp_args[@]}"}
    -v nuget-perf-cache:/tmp/nuget-cache
    -v "$WT_CSHARP:/repo/csharp"
    -w /repo/csharp
)

PREFLIGHT_OUTPUT="$RESULTS_DIR/preflight_output.txt"

echo "  Building..."
if ! docker run "${preflight_docker_common[@]}" \
    "$DOCKER_IMAGE" \
    sh -c "dotnet restore perf/AdbcDrivers.BigQuery.Perf.csproj && dotnet build perf/AdbcDrivers.BigQuery.Perf.csproj -c Release --no-restore" \
    > "$PREFLIGHT_OUTPUT" 2>&1; then

    echo "  ❌ Build FAILED during preflight"
    echo ""
    tail -20 "$PREFLIGHT_OUTPUT"
    echo "BUILD_FAILED" > "$RESULTS_DIR/preflight_status"
    date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/preflight_completed"
    write_perftests_md || true
    exit 1
fi

echo "  Running metadata connectivity check..."
if docker run "${preflight_docker_common[@]}" \
    -e "BIGQUERY_PERF_CONFIG_FILE=/repo/perfconfig.json" \
    -v "$CONFIG_FILE:/repo/perfconfig.json:ro" \
    "$DOCKER_IMAGE" \
    dotnet test perf/AdbcDrivers.BigQuery.Perf.csproj \
        -c Release \
        --no-build \
        --logger "console;verbosity=detailed" \
        --filter "$PREFLIGHT_FILTER" \
    >> "$PREFLIGHT_OUTPUT" 2>&1; then

    echo "  ✅ Metadata connectivity verified"
    echo "PASSED" > "$RESULTS_DIR/preflight_status"
else
    echo "  ❌ Metadata connectivity check FAILED"
    echo ""
    echo "  Cannot reach BigQuery metadata APIs or authenticate. Aborting suite."
    echo ""
    echo "--- Preflight output (last 30 lines) ---"
    tail -30 "$PREFLIGHT_OUTPUT"
    echo "FAILED" > "$RESULTS_DIR/preflight_status"
    date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/preflight_completed"
    write_perftests_md || true
    exit 1
fi
date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/preflight_completed"

# ----- run baseline -----
if [[ "$SKIP_BASELINE" == false ]]; then
    run_perf_test "Baseline (no patches) @ $COMMIT_SHORT" "baseline"
    write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
    echo "  → $OUTPUT_FILE updated"
    if [[ "$TOTAL_PATCHES" -gt 0 ]]; then
        cooldown_between_runs
    fi
fi

# ----- run stacked patches -----
for ((i = 0; i < TOTAL_PATCHES; i++)); do
    patch_file="${PATCH_FILES[$i]}"
    patch_name="$(basename "$patch_file" .patch)"

    echo ""
    echo "Applying patch $((i+1))/$TOTAL_PATCHES: $patch_name"

    cd "$WORKTREE_DIR"
    if ! git apply --check "$patch_file" 2>/dev/null; then
        echo "  ⚠️  Patch does not apply cleanly with git apply, trying with --3way..."
        if ! git apply --3way "$patch_file" 2>/dev/null; then
            echo "  ⚠️  --3way failed, trying fuzzy apply..."
            if ! patch -p1 --fuzz=3 < "$patch_file" 2>/dev/null; then
                echo "  ❌ Patch $patch_name FAILED to apply. Skipping."
                echo "PATCH_FAILED" > "$RESULTS_DIR/patch$(printf '%02d' $((i+1)))_status"
                date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/patch$(printf '%02d' $((i+1)))_completed"
                write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
                echo "  → $OUTPUT_FILE updated"
                continue
            fi
        fi
    else
        if ! git apply "$patch_file"; then
            echo "  ❌ Patch $patch_name FAILED to apply (apply after successful check). Skipping."
            echo "PATCH_FAILED" > "$RESULTS_DIR/patch$(printf '%02d' $((i+1)))_status"
            date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/patch$(printf '%02d' $((i+1)))_completed"
            write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
            echo "  → $OUTPUT_FILE updated"
            continue
        fi
    fi

    echo "  Patch applied."

    # Filter: if this patch targets the data path, skip the build+test.
    # The patch is already applied above so the cumulative stack remains
    # canonical 1→N for later tested rows; we just don't spend a test
    # run measuring something this script can't see.
    patch_num="${patch_name%%-*}"
    if is_skip_test_patch "$patch_num"; then
        test_id="patch$(printf '%02d' $((i+1)))"
        echo "  ⏭️  Skipping test — patch targets the data path (see run-perf-suite.sh)"
        echo "OTHER_PATH" > "$RESULTS_DIR/${test_id}_status"
        date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESULTS_DIR/${test_id}_completed"
        write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
        echo "  → $OUTPUT_FILE updated"
        continue
    fi

    run_perf_test "Patch $((i+1)): $patch_name (cumulative) @ $COMMIT_SHORT" "patch$(printf '%02d' $((i+1)))"
    write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
    echo "  → $OUTPUT_FILE updated"

    # Smart cooldown: only wait if at least one upcoming patch will
    # actually be tested. Avoids burning the cooldown after the last
    # tested run when only filtered (OTHER_PATH) patches remain.
    will_test_more=false
    for ((j = i + 1; j < TOTAL_PATCHES; j++)); do
        next_basename="$(basename "${PATCH_FILES[$j]}" .patch)"
        next_num="${next_basename%%-*}"
        if ! is_skip_test_patch "$next_num"; then
            will_test_more=true
            break
        fi
    done
    if [[ "$will_test_more" == true ]]; then
        cooldown_between_runs
    fi
done

SUITE_COMPLETED=true

echo ""
echo "Done! 🎉"
