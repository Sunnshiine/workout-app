#!/usr/bin/env bash
# shellcheck disable=SC2016  # stubs hold literal $
set -uo pipefail
# CI sets GITHUB_ACTIONS, under which test-log-summary.sh adds ::error lines these checks do not expect.
unset GITHUB_ACTIONS

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$root/bin"
cp "$script_dir/../crap.sh" "$script_dir/../test-log-summary.sh" "$script_dir/../test-log-summary.awk" "$repo/scripts/"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

for tool in swift xcodebuild; do
    printf '#!/bin/sh\ncat "$STUB_LOG"\nexit "${STUB_RC:-1}"\n' >"$root/bin/$tool"
done
cat >"$root/bin/gh" <<'STUB'
#!/bin/sh
printf '978\tsyncLaunchesTheExerciseHistoryFillWithoutWaitingForIt exceeds its 60 s time limit under flake-hunt\n'
printf '1014\taSlowSyncLaunchBootsWithoutWaitingOnTheHold fails under host load\n'
STUB
chmod +x "$root/bin/"*

# The issues sit above the last 40 lines, where a real run leaves them.
log() {
    printf '%s\n' "◇ Test run started." \
        "✘ Test scratchProbeFailsWithNoOpenIssue() recorded an issue at ScratchFailingProbeTests.swift:5:5: Expectation failed: loggedSets.count == 3" \
        "↳ loggedSets.count == 3 → false" \
        "↳   loggedSets.count → 2" \
        "✘ Test scratchProbeFailsWithNoOpenIssue() failed after 0.573 seconds with 1 issue." \
        "✘ Test syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() recorded an issue at SyncCoordinatorTests.swift:192:5: Expectation failed: 1 + 1 == 3" \
        "↳ scratch: fails on purpose" \
        "↳ 1 + 1 == 3 → false" \
        "↳   1 + 1 → 2"
    for i in $(seq 1 45); do echo "✔ Test passes$i() passed after 0.001 seconds."; done
    echo "✘ Test syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() failed after 11.732 seconds with 1 issue."
    echo "✘ Test run with 1279 tests in 15 suites failed after 14.153 seconds with 37 issues (including 35 known issues)."
}
summary="✘ Test scratchProbeFailsWithNoOpenIssue() recorded an issue at ScratchFailingProbeTests.swift:5:5: Expectation failed: loggedSets.count == 3
↳   loggedSets.count → 2
✘ Test scratchProbeFailsWithNoOpenIssue() failed after 0.573 seconds with 1 issue.
✘ Test syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() recorded an issue at SyncCoordinatorTests.swift:192:5: Expectation failed: 1 + 1 == 3
↳ scratch: fails on purpose
↳   1 + 1 → 2
✘ Test syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() failed after 11.732 seconds with 1 issue.
✘ Test run with 1279 tests in 15 suites failed after 14.153 seconds with 37 issues (including 35 known issues)."
issues="no open issue names scratchProbeFailsWithNoOpenIssue
open issue #978: syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt exceeds its 60 s time limit under flake-hunt"
seelog="crap.sh: tests failed; see .build/crap/test.log"

check() {
    local name=$1 want=$2 want_status=${WANT_STATUS:-1}
    shift 2
    STUB_LOG=$root/test.log PATH="$root/bin:$PATH" "$repo/scripts/crap.sh" gate "$@" >"$root/out" 2>"$root/err"
    local status=$? got
    got=$(cat "$root/out" "$root/err")
    if [ "$status" = "$want_status" ] && [ "$got" = "$want" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    got:\n%s\n    want:\n%s\n' "$got" "$want"
    fi
}

log >"$root/test.log"
check "a failing swift test run names each failing test, where and why it failed, and its open issue" \
"$summary
$issues
$seelog"

{ log; printf '%s\n' "" "Failing tests:" "	scratchProbeFailsWithNoOpenIssue()" \
    "	syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt()" "" "** TEST FAILED **" "" "Testing started"; } >"$root/test.log"
check "a failing xcodebuild run names each failing test, where and why it failed, and its open issue" \
"$summary
Failing tests:
	scratchProbeFailsWithNoOpenIssue()
	syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt()
$issues
$seelog" --xcodebuild "$root/xcodebuild"

{ echo "[12/280] Compiling WorkoutTracker SyncCoordinator.swift"
    echo "$repo/Sources/WorkoutTracker/Sync/SyncCoordinator.swift:42:9: error: cannot find 'flushh' in scope"
    echo "        flushh()"
    for i in $(seq 1 45); do echo "[$i/280] Compiling WorkoutTracker File$i.swift"; done
    echo "error: fatalError"; } >"$root/test.log"
check "a build that fails names its compiler errors" \
"$repo/Sources/WorkoutTracker/Sync/SyncCoordinator.swift:42:9: error: cannot find 'flushh' in scope
error: fatalError
$seelog"

log >"$root/test.log"
printf '#!/bin/sh\nexec sleep 30\n' >"$root/bin/gh"
start=$(date +%s)
WORKOUT_ISSUE_WAIT=1 check "a gh that never answers is given up on, and the run still fails" \
"$summary
no issue lookup: gh issue list gave no answer in 1 s
$seelog"
elapsed=$(($(date +%s) - start))
if [ "$elapsed" -lt 10 ]; then ok "the hung lookup returned in ${elapsed} s"; else bad "the hung lookup took ${elapsed} s"; fi

printf '#!/bin/sh\necho "To get started with GitHub CLI, please run:  gh auth login" >&2\nexit 4\n' >"$root/bin/gh"
check "a gh that cannot answer leaves the summary alone" \
"$summary
$seelog"

printf '%s\n' "warning: No matching test cases were run" "✔ Test run with 0 tests in 0 suites passed after 0.001 seconds." >"$root/test.log"
STUB_RC=0 WANT_STATUS=65 check "a swift test run in which no test ran says so and exits 65 before it scores coverage" \
    "crap.sh: no test ran; see .build/crap/test.log"
STUB_RC=0 WANT_STATUS=65 check "an xcodebuild run in which no test ran says so and exits 65 before it scores coverage" \
    "crap.sh: no test ran; see .build/crap/test.log" --xcodebuild "$root/xcodebuild"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
