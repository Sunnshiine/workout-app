#!/bin/bash
set -euo pipefail

if [ $# != 1 ]; then
    cat >&2 <<'USAGE'
Usage: scripts/keyboard-lane-paths.sh <base>
Prints run=true on stdout when the diff from <base> to HEAD touches a file KeyboardLaneUITests
reaches, and run=false otherwise, and names the paths that matched on stderr. The tests reach what
the WorkoutTracker app and WorkoutTrackerUITests targets compile (App/, Sources/WorkoutTracker/,
WorkoutShared/, Tests/UI/), the project that defines those targets (WorkoutTracker.xcodeproj/), and
the lane's wiring (.github/workflows/ci.yml, scripts/ci-keyboard-lane.sh,
scripts/keyboard-lane-paths.sh, scripts/sim-keyboard.sh). The rule below lists those folders by
hand. scripts/tests/keyboard-lane-paths.test.sh reads the two targets' synchronized groups from
project.pbxproj and fails when the rule misses one. Script tests runs it when a scripts/ file or
project.pbxproj changes. scripts/ci-keyboard-lane.sh runs the lane on run=true.
Exits 2 on bad arguments and with git's status when the diff fails.
USAGE
    exit 2
fi

reached='^(App/|Sources/WorkoutTracker/|WorkoutShared/|Tests/UI/|WorkoutTracker\.xcodeproj/|\.github/workflows/ci\.yml$|scripts/(ci-keyboard-lane|keyboard-lane-paths|sim-keyboard)\.sh$)'
changed=$(git diff --name-only "$1" HEAD)
matched=$(printf '%s\n' "$changed" | grep -E "$reached") || [ $? = 1 ]
if [ -z "$matched" ]; then
    echo "keyboard lane: no path it reaches changed" >&2
    echo run=false
    exit 0
fi
echo "keyboard lane: runs for" >&2
printf '%s\n' "$matched" | sed 's/^/  /' >&2
echo run=true
