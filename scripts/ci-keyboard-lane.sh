#!/bin/bash
set -uo pipefail

if [ $# != 1 ] || [ -z "${RUNNER_TEMP:-}" ]; then
    cat >&2 <<'USAGE'
Usage: RUNNER_TEMP=<dir> scripts/ci-keyboard-lane.sh <udid>
CI's keyboard lane: runs KeyboardLaneUITests animated on <udid>, reusing the DerivedData, package
checkouts, and compilation cache the visual-tests job keeps under RUNNER_TEMP, and writes
KeyboardLane.xcresult. Resets the simulator's keyboard preference first (scripts/sim-keyboard.sh,
#700) and prints it before and after the run. Stops any one test after 3 minutes, so a hung test
fails and the run goes on. Exits with xcodebuild's status, or 1 when xcodebuild passes but the
bundle shows a different number of tests ran, skipped ones excluded, than
KeyboardLaneUITests.swift declares.
Locally, run scripts/test-sim.sh WorkoutTrackerUITests/KeyboardLaneUITests instead.
USAGE
    exit 2
fi

sim=$1
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
bundle=KeyboardLane.xcresult

preference() {
    echo "keyboard preference $1 the lane: $(xcrun simctl spawn "$sim" defaults read \
        com.apple.keyboard.preferences AutomaticMinimizationEnabled 2>&1)"
}

scripts/sim-keyboard.sh ensure "$sim" || exit
preference before
trap 'preference after' EXIT

status=0
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
    -destination "platform=iOS Simulator,id=$sim" \
    -only-testing:WorkoutTrackerUITests/KeyboardLaneUITests \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" \
    -clonedSourcePackagesDirPath "$RUNNER_TEMP/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile \
    -resultBundlePath "$bundle" \
    -collect-test-diagnostics never \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 180 \
    -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_CAS_PATH="$RUNNER_TEMP/CompilationCache" || status=$?
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
