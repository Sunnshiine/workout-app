#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SUBCOMMAND="measure"
RUN_TESTS=1
THRESHOLD=6
TOLERANCE=0.5
TOP=25
XCODEBUILD_DIR=""

usage() {
    cat <<'EOF'
scripts/crap.sh [measure|gate|baseline] [options]

  measure    Score every production function and print the worst ones (default).
  gate       Fail if a function is a new or worsened violation, or if the baseline is stale.
  baseline   Rewrite tools/crap/baseline.tsv from the current report.

  --no-test          Reuse the existing coverage profile instead of running swift test.
  --xcodebuild DIR   Run the tests with xcodebuild and its compilation cache instead of swift test.
                     DIR holds DerivedData, SourcePackages, and CompilationCache. Cache hits need
                     the same absolute paths for the checkout and DIR on every run (CI).
  --top N            Rows to print for measure (default 25).
  --threshold N      CRAP a function must stay at or below (default 6).
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
        --xcodebuild)
            XCODEBUILD_DIR="$2"
            shift
            ;;
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
PROFILES="$(dirname "$PROFDATA")"
if [[ -n $XCODEBUILD_DIR ]]; then
    PROFILES="$XCODEBUILD_DIR/DerivedData/Build/ProfileData"
fi
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
    local log="$OUT/test.log"
    rm -rf "$PROFILES"
    if ! test_command >"$log" 2>&1; then
        tail -40 "$log" >&2
        echo "crap.sh: tests failed; see $log" >&2
        exit 1
    fi
    grep -E '^.?.?Test run with' "$log" | tail -1 || true
}

test_command() {
    if [[ -z $XCODEBUILD_DIR ]]; then
        swift test --enable-code-coverage
        return
    fi
    # The sibling WorkoutTracker.xcodeproj would win over Package.swift, so name the package
    # workspace Xcode generates when it opens the package.
    local workspace=".swiftpm/xcode/package.xcworkspace"
    mkdir -p "$workspace"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n<FileRef location = "self:"></FileRef>\n</Workspace>\n' \
        >"$workspace/contents.xcworkspacedata"
    xcodebuild test -workspace "$workspace" -scheme WorkoutTracker -destination platform=macOS \
        -enableCodeCoverage YES -collect-test-diagnostics never \
        -skipPackagePluginValidation -skipMacroValidation \
        -derivedDataPath "$XCODEBUILD_DIR/DerivedData" \
        -clonedSourcePackagesDirPath "$XCODEBUILD_DIR/SourcePackages" \
        COMPILATION_CACHE_ENABLE_CACHING=YES \
        COMPILATION_CACHE_CAS_PATH="$XCODEBUILD_DIR/CompilationCache"
}

export_lcov() {
    local bin
    if [[ -n $XCODEBUILD_DIR ]]; then
        PROFDATA="$(find "$PROFILES" -name Coverage.profdata 2>/dev/null | head -1 || true)"
        bin="$XCODEBUILD_DIR/DerivedData/Build/Products/Debug"
    else
        bin="$(swift build --show-bin-path)"
    fi
    if [[ ! -f $PROFDATA ]]; then
        echo "crap.sh: no coverage profile in $PROFILES. Run without --no-test first." >&2
        exit 1
    fi
    local test_binary="$bin/WorkoutTrackerTests.xctest/Contents/MacOS/WorkoutTrackerTests"
    if [[ ! -f $test_binary ]]; then
        echo "crap.sh: test binary not found at $test_binary. Run without --no-test first." >&2
        exit 1
    fi
    xcrun llvm-cov export -format=lcov -instr-profile "$PROFDATA" "$test_binary" \
        -ignore-filename-regex='(^|/)(Tests|\.build|SourcePackages)/' >"$LCOV"
}

build_tool() {
    swift build --package-path tools/crap >"$OUT/build.log" 2>&1 ||
        {
            cat "$OUT/build.log" >&2
            exit 1
        }
}

measure() {
    tools/crap/.build/debug/crap measure \
        --root "$ROOT" \
        --lcov "$LCOV" \
        --source Sources/WorkoutTracker \
        --source Sources/WorkoutCLI \
        --threshold "$THRESHOLD" \
        --top "$TOP" \
        --json "$REPORT"
}

if [[ $RUN_TESTS -eq 1 ]]; then
    step "tests with coverage" run_tests
fi
step "llvm-cov export" export_lcov
step "build crap" build_tool

case "$SUBCOMMAND" in
    measure)
        step "measure" measure
        ;;
    gate)
        step "measure" measure >/dev/null
        tools/crap/.build/debug/crap gate \
            --report "$REPORT" --baseline "$BASELINE" \
            --threshold "$THRESHOLD" --tolerance "$TOLERANCE"
        ;;
    baseline)
        step "measure" measure >/dev/null
        tools/crap/.build/debug/crap baseline \
            --report "$REPORT" --write "$BASELINE" --threshold "$THRESHOLD"
        ;;
esac
