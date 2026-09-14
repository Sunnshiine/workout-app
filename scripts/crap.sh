#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SUBCOMMAND="measure"
RUN_TESTS=1
THRESHOLD=12
TOLERANCE=0.5
TOP=25

usage() {
    cat <<'EOF'
scripts/crap.sh [measure|gate|baseline] [options]

  measure    Score every production function and print the worst ones (default).
  gate       Fail if a function is a new or worsened violation, or if the baseline is stale.
  baseline   Rewrite tools/crap/baseline.tsv from the current report.

  --no-test          Reuse the existing coverage profile instead of running swift test.
  --top N            Rows to print for measure (default 25).
  --threshold N      CRAP a function must stay at or below (default 12).
  --tolerance N      Slack before a baselined function counts as worsened (default 0.5).
  -h, --help         Show this message.

Artifacts: .build/crap/coverage.lcov, .build/crap/report.json, tools/crap/baseline.tsv
EOF
}

case "${1:-}" in
    measure | gate | baseline)
        SUBCOMMAND="$1"
        shift
        ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-test) RUN_TESTS=0 ;;
        --top)
            TOP="$2"
            shift
            ;;
        --threshold)
            THRESHOLD="$2"
            shift
            ;;
        --tolerance)
            TOLERANCE="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "crap.sh: unknown option $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

OUT=".build/crap"
LCOV="$OUT/coverage.lcov"
REPORT="$OUT/report.json"
BASELINE="tools/crap/baseline.tsv"
PROFDATA=".build/debug/codecov/default.profdata"
mkdir -p "$OUT"

step() {
    local label="$1"
    shift
    local start
    start=$(date +%s)
    "$@"
    echo "[crap] $label: $(($(date +%s) - start))s" >&2
}

run_tests() {
    local log="$OUT/swift-test.log"
    if ! swift test --enable-code-coverage >"$log" 2>&1; then
        tail -40 "$log" >&2
        echo "crap.sh: swift test failed; see $log" >&2
        exit 1
    fi
    grep -E '^.?.?Test run with' "$log" | tail -1 || true
}

export_lcov() {
    if [[ ! -f $PROFDATA ]]; then
        echo "crap.sh: no coverage profile at $PROFDATA. Run without --no-test first." >&2
        exit 1
    fi
    local bin
    bin="$(swift build --show-bin-path)"
    local test_binary="$bin/WorkoutTrackerTests.xctest/Contents/MacOS/WorkoutTrackerTests"
    if [[ ! -f $test_binary ]]; then
        echo "crap.sh: test binary not found at $test_binary. Run without --no-test first." >&2
        exit 1
    fi
    xcrun llvm-cov export -format=lcov -instr-profile "$PROFDATA" "$test_binary" \
        -ignore-filename-regex='(^|/)(Tests|\.build)/' >"$LCOV"
}

build_tool() {
    swift build --package-path tools/crap -c release >"$OUT/build.log" 2>&1 ||
        {
            cat "$OUT/build.log" >&2
            exit 1
        }
}

measure() {
    tools/crap/.build/release/crap measure \
        --root "$ROOT" \
        --lcov "$LCOV" \
        --source WorkoutTracker \
        --source WorkoutCLI \
        --exclude 'WorkoutTracker/Views/*' \
        --exclude 'WorkoutTracker/LiveActivity/*' \
        --exclude 'WorkoutTracker/Sheets/GoogleAuth.swift' \
        --exclude 'WorkoutTracker/WorkoutTrackerApp.swift' \
        --threshold "$THRESHOLD" \
        --top "$TOP" \
        --json "$REPORT"
}

if [[ $RUN_TESTS -eq 1 ]]; then
    step "swift test --enable-code-coverage" run_tests
fi
step "llvm-cov export" export_lcov
step "build crap" build_tool

case "$SUBCOMMAND" in
    measure)
        step "measure" measure
        ;;
    gate)
        step "measure" measure >/dev/null
        tools/crap/.build/release/crap gate \
            --report "$REPORT" --baseline "$BASELINE" \
            --threshold "$THRESHOLD" --tolerance "$TOLERANCE"
        ;;
    baseline)
        step "measure" measure >/dev/null
        tools/crap/.build/release/crap baseline \
            --report "$REPORT" --write "$BASELINE" --threshold "$THRESHOLD"
        ;;
esac
