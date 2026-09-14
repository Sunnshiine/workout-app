#!/usr/bin/env bash
# Runs simulator test suites the fast way: one build-for-testing, then every requested suite in a
# single test-without-building session driven by the xctestrun file, so xcodebuild never loads the
# project or resolves the package graph a second time.
#
# Usage: scripts/test-sim.sh [--no-build] [--sim UDID] <unit|visual|ui|all|TEST-ID>...
#   unit    WorkoutTrackerTests (hosted unit + component; the same tests as `swift test` plus UIKit-only ones)
#   visual  WorkoutTrackerSnapshotTests (ADR-0007 gate)
#   ui      WorkoutTrackerUITests
#   TEST-ID any -only-testing identifier, e.g. WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testMoveOnAdvancesToNextExercise
# --no-build reuses the last build-for-testing; use it when only the test selection changed.
# The simulator is the booted iPhone 17 Pro, or the newest available one, which the script boots.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
project=$repo/WorkoutTracker.xcodeproj
build=1
sim=${SIM:-}
targets=()

while [ $# -gt 0 ]; do
  case $1 in
    --no-build) build=0 ;;
    --sim) sim=$2; shift ;;
    unit) targets+=(-only-testing:WorkoutTrackerTests) ;;
    visual) targets+=(-only-testing:WorkoutTrackerSnapshotTests) ;;
    ui) targets+=(-only-testing:WorkoutTrackerUITests) ;;
    all) targets+=(-only-testing:WorkoutTrackerTests -only-testing:WorkoutTrackerSnapshotTests -only-testing:WorkoutTrackerUITests) ;;
    -*) echo "unknown flag $1" >&2; exit 2 ;;
    *) targets+=("-only-testing:$1") ;;
  esac
  shift
done
[ ${#targets[@]} -gt 0 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

if [ -z "$sim" ]; then
  sim=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
def version(runtime): return tuple(int(n) for n in runtime.rsplit("iOS-", 1)[-1].split("-"))
devices = [(version(runtime), d) for runtime, ds in json.load(sys.stdin)["devices"].items() for d in ds if d["name"] == "iPhone 17 Pro"]
booted = [d for d in devices if d[1]["state"] == "Booted"]
pick = max(booted or devices, key=lambda pair: pair[0])[1]
print(pick["udid"], pick["state"])')
  read -r sim state <<< "$sim"
  [ "$state" = Booted ] || xcrun simctl boot "$sim"
fi
destination="platform=iOS Simulator,id=$sim"

logs=$repo/.build/test-sim
mkdir -p "$logs"
stamp=$(date +%Y%m%d-%H%M%S)

if [ $build = 1 ]; then
  xcodebuild build-for-testing -project "$project" -scheme WorkoutTracker -destination "$destination" \
    -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO > "$logs/$stamp-build.log" 2>&1 \
    || { grep -E "error:|BUILD FAILED" "$logs/$stamp-build.log" | head -20 >&2; echo "build log: $logs/$stamp-build.log" >&2; exit 65; }
fi

xctestrun=$(for plist in ~/Library/Developer/Xcode/DerivedData/WorkoutTracker-*/info.plist; do
  [ "$(plutil -extract WorkspacePath raw "$plist")" = "$project" ] && ls -t "$(dirname "$plist")"/Build/Products/WorkoutTracker_iphonesimulator*.xctestrun 2>/dev/null | head -1
done | head -1)
[ -n "$xctestrun" ] || { echo "no xctestrun for $project; run without --no-build" >&2; exit 65; }

set +e
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO "${targets[@]}" > "$logs/$stamp-test.log" 2>&1
rc=$?
set -e
grep -E "^(✔|✘) Test run with|Executed [1-9][0-9]* tests?, with|error: .*\.swift:[0-9]+|^Failing tests:|^	[A-Za-z_.]+(\(\))?$|\*\* TEST EXECUTE" "$logs/$stamp-test.log" | uniq
echo "log: $logs/$stamp-test.log"
exit $rc
