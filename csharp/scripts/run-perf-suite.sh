#!/usr/bin/env bash
#
# run-perf-suite.sh — Stacked patch performance test orchestrator
#
# Runs the BigQuery ADBC C# performance tests with patches applied
# incrementally. Each test level stacks one more patch on top of
# the previous, measuring cumulative impact.
#
# Results are written to PERFTESTS.md with both a summary table
# and detailed per-test sections. The file is atomically updated
# after each test run so it always reflects the latest state, even
# if the suite is interrupted.
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
#   --cooldown SECS     Seconds to wait between test runs to mitigate BQ throttling (default: 60)
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
COOLDOWN_SECS=60  # seconds to wait between test runs to mitigate BQ throttling

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

# ----- create worktree -----
WORKTREE_DIR="$(mktemp -d)"
echo "Creating worktree at $WORKTREE_DIR ..."

cleanup() {
    echo ""
    # Write final PERFTESTS.md only on abnormal exit (interrupt/error).
    # Normal completion already wrote the final version in the main loop.
    if [[ "$SUITE_COMPLETED" == false ]] && [[ -n "${RESULTS_DIR:-}" ]] && [[ -d "$RESULTS_DIR" ]]; then
        write_perftests_md || true
        echo "Results saved to $OUTPUT_FILE"
    fi
    # Clean up any leftover temp files from atomic writes
    rm -f "${OUTPUT_FILE}.tmp."* 2>/dev/null || true
    echo "Cleaning up worktree..."
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

    # Clean previous build artifacts (src only + perf binaries, NOT arrow-adbc)
    # This ensures patches get a fresh build instead of stale incremental results.
    # We preserve perf/obj because it contains project.assets.json (NuGet restore
    # metadata). The perf project doesn't change between patches, so its restore
    # state is stable. Deleting it causes "Could not find project.assets.json"
    # errors because dotnet build's implicit restore doesn't always recreate it.
    echo "  Cleaning build artifacts..."
    rm -rf "$wt_csharp/src/obj" "$wt_csharp/src/bin"
    rm -rf "$wt_csharp/perf/bin"
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

    # Common docker args for both build and test containers.
    # The volume mounts ensure build artifacts persist across containers.
    local -a docker_common=(
        --rm
        ${env_args[@]+"${env_args[@]}"}
        ${gcp_cred_args[@]+"${gcp_cred_args[@]}"}
        -v nuget-perf-cache:/root/.nuget/packages
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
        # Copy build output as main output for error reporting
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
    echo "  Running perf test..."
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
    #
    # NOTE: Each extraction uses `{ sed ... || true; }` to prevent SIGPIPE
    # failures. When `head -1` closes the pipe after the first match, sed
    # receives SIGPIPE and exits with 141. Under `set -o pipefail`, this
    # would propagate as a non-zero pipeline exit, causing `set -e` to
    # abort the entire script mid-write of PERFTESTS.md — truncating the
    # file and losing all accumulated results.
    local total_rows total_batches total_time throughput_rows throughput_bytes

    total_rows=$({ sed -n 's/.*Total rows:[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" || true; } | head -1)
    total_batches=$({ sed -n 's/.*Total batches:[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" || true; } | head -1)
    # Total time is in TimeSpan format: "00:47:25.3457848"
    total_time=$({ sed -n 's/.*Total:[[:space:]]*\([0-9.:]*\).*/\1/p' "$output_file" || true; } | head -1)
    # Rows/sec (read): 8,812
    throughput_rows=$({ sed -n 's/.*Rows\/sec (read):[[:space:]]*\([0-9,]*\).*/\1/p' "$output_file" || true; } | head -1)
    # Bytes/sec (read): 1,381,763 (1.32 MB/s)
    throughput_bytes=$({ sed -n 's/.*Bytes\/sec (read):[[:space:]]*[0-9,]* (\([^)]*\)).*/\1/p' "$output_file" || true; } | head -1)
    # Throttle stats from the driver's MultiArrowReader
    max_throttle=$({ sed -n 's/.*Max throttle:[[:space:]]*\([0-9]*\)%.*/\1/p' "$output_file" || true; } | head -1)
    avg_throttle=$({ sed -n 's/.*Avg throttle:[[:space:]]*\([0-9.]*\)%.*/\1/p' "$output_file" || true; } | head -1)

    echo "${total_rows:-N/A}|${total_batches:-N/A}|${total_time:-N/A}|${throughput_rows:-N/A}|${throughput_bytes:-N/A}|${max_throttle:-N/A}|${avg_throttle:-N/A}"
}

# ----- helper: status emoji -----
status_emoji() {
    case "$1" in
        PASSED)            echo "✅" ;;
        PENDING)           echo "⏳" ;;
        SKIPPED|NO_TESTS)  echo "⚠️" ;;
        *)                 echo "❌" ;;
    esac
}

# ----- helper: (re)generate PERFTESTS.md from current results -----
# Called after every test run so the file always reflects the latest state.
# Tests not yet started appear as ⏳ PENDING.
#
# Uses atomic writes: generates content in a temp file, then renames it
# to the output path. This prevents data loss if the script is killed
# mid-write (a bare `> file` would truncate first, leaving partial content).
write_perftests_md() {
    local tmp_file
    tmp_file="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"

    {
        echo "# Performance Test Results"
        echo ""
        echo "**Commit:** \`$COMMIT_SHA\`"
        echo "**Suite started:** $SUITE_START_TIME"
        echo "**Last updated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "**Patches:** $TOTAL_PATCHES applied incrementally"
        echo "**Cooldown between runs:** ${COOLDOWN_SECS}s"
        echo ""

        # Summary table
        echo "## Summary"
        echo ""
        echo "| # | Configuration | Status | Build (s) | Test (s) | Completed | Total Rows | Total Batches | Total Time | Throughput (rows/s) | Throughput (bytes/s) | Max Throttle | Avg Throttle |"
        echo "|---|--------------|--------|----------|---------|-----------|-----------|--------------|------------|--------------------|--------------------|-------------|-------------|"

        # Baseline row
        if [[ "$SKIP_BASELINE" == false ]]; then
            local status completed emoji metrics rows batches time thr_rows thr_bytes
            local build_time test_time
            status=$(cat "$RESULTS_DIR/baseline_status" 2>/dev/null || echo "PENDING")
            completed=$(cat "$RESULTS_DIR/baseline_completed" 2>/dev/null || echo "-")
            build_time=$(cat "$RESULTS_DIR/baseline_buildtime" 2>/dev/null || echo "-")
            test_time=$(cat "$RESULTS_DIR/baseline_wallclock" 2>/dev/null || echo "-")
            emoji=$(status_emoji "$status")
            if [[ "$status" == "PASSED" ]]; then
                metrics=$(parse_test_output "baseline")
                IFS='|' read -r rows batches time thr_rows thr_bytes max_thr avg_thr <<< "$metrics"
                echo "| 0 | Baseline (no patches) | $emoji $status | $build_time | $test_time | $completed | $rows | $batches | $time | $thr_rows | $thr_bytes | ${max_thr}% | ${avg_thr}% |"
            else
                echo "| 0 | Baseline (no patches) | $emoji $status | $build_time | $test_time | $completed | - | - | - | - | - | - | - |"
            fi
        fi

        # Patch rows
        local pi test_id patch_name status completed emoji metrics rows batches time thr_rows thr_bytes
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
                IFS='|' read -r rows batches time thr_rows thr_bytes max_thr avg_thr <<< "$metrics"
                echo "| $((pi+1)) | +$patch_name | $emoji $status | $build_time | $test_time | $completed | $rows | $batches | $time | $thr_rows | $thr_bytes | ${max_thr}% | ${avg_thr}% |"
            else
                echo "| $((pi+1)) | +$patch_name | $emoji $status | $build_time | $test_time | $completed | - | - | - | - | - | - | - |"
            fi
        done

        echo ""

        # Detailed sections
        echo "## Detailed Results"
        echo ""

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

            # Only emit detail section if the test has run
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
        echo "*Generated by \`run-perf-suite.sh\` on $(date -u '+%Y-%m-%d %H:%M:%S UTC')*"

    } > "$tmp_file"

    # Atomic rename — if this succeeds, the output file is always complete.
    # If the script is killed before this point, the previous PERFTESTS.md
    # (from the last successful write) remains intact.
    mv -f "$tmp_file" "$OUTPUT_FILE"
}

# ----- helper: cooldown between test runs -----
# Mitigates BigQuery Storage Read API server-side throttling by waiting
# between consecutive reads. The API dynamically throttles per-connection
# throughput (via ThrottleState.throttle_percent in ReadRowsResponse) when
# a project sustains high read volume. A pause lets the throttle dissipate.
cooldown_between_runs() {
    if [[ "$COOLDOWN_SECS" -le 0 ]]; then
        return
    fi
    echo ""
    echo "  ⏳ Cooldown: waiting ${COOLDOWN_SECS}s to mitigate BigQuery throttling..."
    local remaining=$COOLDOWN_SECS
    while [[ $remaining -gt 0 ]]; do
        printf "\r  ⏳ Cooldown: %3ds remaining..." "$remaining"
        sleep 1
        remaining=$((remaining - 1))
    done
    printf "\r  ✅ Cooldown complete.                    \n"
}

# ----- run baseline -----
if [[ "$SKIP_BASELINE" == false ]]; then
    run_perf_test "Baseline (no patches) @ $COMMIT_SHORT" "baseline"
    write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
    echo "  → $OUTPUT_FILE updated"
    # Cooldown before the first patch run
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

    # Apply patch to worktree
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

    run_perf_test "Patch $((i+1)): $patch_name (cumulative) @ $COMMIT_SHORT" "patch$(printf '%02d' $((i+1)))"
    write_perftests_md || echo "  ⚠️  Warning: failed to update $OUTPUT_FILE"
    echo "  → $OUTPUT_FILE updated"

    # Cooldown before next patch (skip after the last one)
    if [[ $((i + 1)) -lt $TOTAL_PATCHES ]]; then
        cooldown_between_runs
    fi
done

SUITE_COMPLETED=true

echo ""
echo "Done! 🎉"
