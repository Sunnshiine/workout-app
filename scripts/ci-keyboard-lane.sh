#!/bin/bash
set -uo pipefail

if [ $# != 2 ]; then
    cat >&2 <<'USAGE'
Usage: scripts/ci-keyboard-lane.sh <udid> <xctestrun>
CI's keyboard lane. On a pull_request event it asks scripts/keyboard-lane-paths.sh whether the
change since HEAD^1 reaches the lane and exits 0 when it does not. On any other event it runs only
when DISPATCHED is true (`gh workflow run ci.yml -f keyboard-lane=true`). Then it resets the
simulator's keyboard preference (scripts/sim-keyboard.sh, #700), prints it before and after, and
runs KeyboardLaneUITests animated from the visual-tests build into KeyboardLane.xcresult. A test
still running after 3 minutes fails and the run goes on. Appends KEYBOARD_LANE_SECONDS to
GITHUB_ENV when that is set, so the job's speed budget can leave the lane out.
Exits with xcodebuild's status, or 1 when xcodebuild passes but the bundle shows a different
number of tests ran, skipped ones excluded, than KeyboardLaneUITests.swift declares.
Locally, run scripts/test-sim.sh WorkoutTrackerUITests/KeyboardLaneUITests instead.
USAGE
    exit 2
fi

sim=$1
xctestrun=$2
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
bundle=KeyboardLane.xcresult

if [ "${GITHUB_EVENT_NAME:-}" = pull_request ]; then
    decision=$(scripts/keyboard-lane-paths.sh HEAD^1) || exit
    [ "$decision" = run=true ] || exit 0
elif [ "${DISPATCHED:-}" != true ]; then
    echo "keyboard lane: not a pull request, and not dispatched with keyboard-lane=true"
    exit 0
fi

start=$SECONDS
preference() {
    echo "keyboard preference $1 the lane: $(xcrun simctl spawn "$sim" defaults read \
        com.apple.keyboard.preferences AutomaticMinimizationEnabled 2>&1)"
}
finish() {
    preference after
    [ -z "${GITHUB_ENV:-}" ] || echo "KEYBOARD_LANE_SECONDS=$((SECONDS - start))" >>"$GITHUB_ENV"
}

scripts/sim-keyboard.sh ensure "$sim" || exit
preference before
trap finish EXIT

status=0
xcodebuild test-without-building -xctestrun "$xctestrun" \
    -destination "platform=iOS Simulator,id=$sim" \
    -only-testing:WorkoutTrackerUITests/KeyboardLaneUITests \
    -resultBundlePath "$bundle" \
    -collect-test-diagnostics never \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 180 || status=$?
[ "$status" = 0 ] || exit "$status"

declared=$(grep -cE '^    func test' Tests/UI/KeyboardLaneUITests.swift)
ran=$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null | python3 -c '
import json, sys
s = json.load(sys.stdin)
print(s["passedTests"] + s["failedTests"] + s["expectedFailures"])' 2>/dev/null) || ran=none
if [ "$ran" != "$declared" ]; then
    echo "::error::KeyboardLaneUITests.swift declares $declared tests and the bundle shows $ran ran."
    exit 1
fi
echo "keyboard lane: $ran of $declared tests ran"
