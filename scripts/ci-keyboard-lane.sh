#!/bin/bash
set -uo pipefail

if [ $# != 2 ]; then
    cat >&2 <<'USAGE'
Usage: scripts/ci-keyboard-lane.sh <udid> <xctestrun>
CI's keyboard lane. On a pull_request event it asks scripts/keyboard-lane-paths.sh whether the
change since HEAD^1 reaches the lane. It exits 0 on run=false and 1 on anything but run=true or
run=false. On any other event it runs only when DISPATCHED is true
(`gh workflow run ci.yml -f keyboard-lane=true`). Then it resets the simulator's keyboard
preference (scripts/sim-keyboard.sh, #700), prints it before and after, and runs
KeyboardLaneUITests animated from the visual-tests build into KeyboardLane.xcresult. A test still
running after 3 minutes fails and the run goes on. Appends KEYBOARD_LANE_SECONDS to GITHUB_ENV
when that is set, so the job's speed budget can leave the lane out.
Exits with xcodebuild's status. Exits 1 when KeyboardLaneUITests.swift declares no test, or when
xcodebuild passes but the bundle shows a different number of tests ran, skipped ones excluded,
than the file declares. A declared test is a `func test...()` on a line that is not a comment.
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
    case $decision in
        run=true) ;;
        run=false) exit 0 ;;
        *)
            echo "::error::keyboard-lane-paths.sh printed '$decision', not run=true or run=false."
            exit 1
            ;;
    esac
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

declared=$(grep -vE '^[[:space:]]*//' Tests/UI/KeyboardLaneUITests.swift \
    | grep -cE '(^|[^[:alnum:]_])func[[:space:]]+test[[:alnum:]_]*[[:space:]]*\([[:space:]]*\)')
if [ "$declared" = 0 ]; then
    echo "::error::KeyboardLaneUITests.swift declares no test."
    exit 1
fi

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

ran=$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null | python3 -c '
import json, sys
s = json.load(sys.stdin)
print(s["passedTests"] + s["failedTests"] + s["expectedFailures"])' 2>/dev/null) || ran=none
if [ "$ran" != "$declared" ]; then
    echo "::error::KeyboardLaneUITests.swift declares $declared tests and the bundle shows $ran ran."
    exit 1
fi
echo "keyboard lane: $ran of $declared tests ran"
