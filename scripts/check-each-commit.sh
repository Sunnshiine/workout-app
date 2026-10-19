#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/check-each-commit.sh BASE..HEAD
       scripts/check-each-commit.sh BASE          (means BASE..HEAD)

Builds and tests every commit in the range, oldest first, in a scratch tree under the primary
checkout's .build/scratch/, never in your worktree. Each commit runs these steps and stops at the
first that fails:
  spm-build  swift build --build-tests
  spm-test   swift test --skip-build
  xcode-bft  xcodebuild build-for-testing: the app, the widget, and the unit, UI, and Visual test
             bundles, for a generic simulator destination, so no simulator boots
Prints one line per commit, verdict first, with each step's time and spm-test's test count. A
failing step shows ✘ and the steps after it -, then its first error line and its log. Every commit
runs. Logs go under .build/check-each-commit/ in your worktree.
Exits 0 when every commit passed, 1 when any failed, 2 on usage or an empty range, 75 when every
scratch tree is busy.
EOF
}

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/scratch-tree.sh
. "$script_dir/scratch-tree.sh"
# shellcheck source=scripts/compile-cache.sh
. "$script_dir/compile-cache.sh"

case ${1:-} in
    -h | --help) usage; exit 0 ;;
    '' | -*) usage >&2; exit 2 ;;
esac
[ $# = 1 ] || { usage >&2; exit 2; }
range=$1
case $range in
    *...*) echo "A...B names both sides of a fork; check-each-commit.sh takes BASE..HEAD" >&2; usage >&2; exit 2 ;;
    *..*) ;;
    *) range=$range..HEAD ;;
esac

caller=$(git rev-parse --show-toplevel)
cd "$caller"
commits=$(git rev-list --reverse "$range" 2>/dev/null) || { echo "not a commit range: $range" >&2; exit 2; }
[ -n "$commits" ] || { echo "no commits in $range" >&2; exit 2; }

logs=$caller/.build/check-each-commit/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$logs"
echo "log: $logs"
scratch_claim "check-each-commit.sh in $caller"
echo "scratch: $scratch"

run_step() {
    case $1 in
        spm-build) swift build --build-tests ;;
        spm-test) swift test --skip-build ;;
        xcode-bft)
            xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
                -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation -skipMacroValidation \
                CODE_SIGNING_ALLOWED=NO ${compile_cache_settings[@]+"${compile_cache_settings[@]}"}
            ;;
    esac
}
read_log() { awk -v mode="$1" -v root="$scratch/" -f "$script_dir/test-log.awk" "$2"; }

failures=0
for commit in $commits; do
    scratch_sync "$commit"
    line="" failed_log=""
    for step in spm-build spm-test xcode-bft; do
        if [ -n "$failed_log" ]; then
            line="$line  $step -"
            continue
        fi
        log=$logs/${commit:0:8}-$step.log
        start=$SECONDS
        if (cd "$scratch" && run_step $step) </dev/null >"$log" 2>&1; then
            line="$line  $step"
            [ $step != spm-test ] || line="$line $(read_log count "$log")"
            line="$line $((SECONDS - start))s"
        else
            line="$line  $step ✘"
            failed_log=$log
        fi
    done
    subject=$(git log -1 --format=%s "$commit")
    if [ -z "$failed_log" ]; then
        echo "ok    ${commit:0:8}$line  $subject"
    else
        failures=$((failures + 1))
        echo "FAIL  ${commit:0:8}$line  $subject"
        echo "      $(read_log first-error "$failed_log")"
        echo "      log: $failed_log"
    fi
done
[ $failures = 0 ] || { echo "$failures of $(echo "$commits" | wc -l | tr -d ' ') commits failed"; exit 1; }
