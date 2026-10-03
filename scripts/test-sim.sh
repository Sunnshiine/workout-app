#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/test-sim.sh [--no-build] [--sim UDID] <unit|visual|ui|all|TEST-ID>...
  unit     WorkoutTrackerTests (the `swift test` suites plus the UIKit-only ones, hosted in the app)
  visual   WorkoutTrackerSnapshotTests (ADR-0007 gate)
  ui       WorkoutTrackerUITests
  TEST-ID  any -only-testing identifier, e.g.
           WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testCurrentSessionLogsFirstSetAndAdvancesActiveSet
Builds once with build-for-testing, then runs every requested suite in one test-without-building
session from the xctestrun file. --no-build reuses the last build when only the selection changed.
Prints the test log path before the run starts. The summary at the end holds the run counts, the
first three issues each test recorded with the values each one compared, every failing test, and
any error or crash that stopped xcodebuild before the run finished.
The simulator is the booted iPhone 17 Pro, else the newest available one, which the script boots.
With no available iPhone 17 Pro it creates one on iOS 27.0 (scripts/ensure-simulator.sh) and boots that.
Refuses (exit 75) while another test-sim.sh run or a verify run's app holds that simulator, and
refuses (exit 2) a --sim UDID that simctl lists no available simulator for.
EOF
  exit 2
}

repo=$(cd "$(dirname "$0")/.." && pwd)
. "$repo/scripts/sim-lock.sh"
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
    -*) usage ;;
    *) targets+=("-only-testing:$1") ;;
  esac
  shift
done
[ ${#targets[@]} -gt 0 ] || usage

picked=$(pick_sim "$sim" create)
read -r sim state <<< "$picked"
[ "$state" != named ] || sim_available "$sim" \
  || { echo "no available simulator $sim; xcrun simctl list devices available lists them" >&2; exit 2; }
[ "$state" != Shutdown ] || xcrun simctl boot "$sim"
claim_sim "$sim" "test-sim.sh run"
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
  if [ "$(plutil -extract WorkspacePath raw "$plist")" = "$project" ]; then
    ls -t "$(dirname "$plist")"/Build/Products/WorkoutTracker_iphonesimulator*.xctestrun 2>/dev/null
  fi
done | head -1) || true
[ -n "$xctestrun" ] || { echo "no xctestrun for $project; run without --no-build" >&2; exit 65; }

log=$logs/$stamp-test.log
echo "log: $log"
set +e
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO "${targets[@]}" > "$log" 2>&1
rc=$?
set -e
if ! awk -f "$repo/scripts/test-log-summary.awk" "$log" | uniq; then
  [ $rc = 0 ] || { echo "xcodebuild exited $rc before the test run finished; the lines above and the log say why" >&2; exit $rc; }
  echo "no tests ran; check the selection (${targets[*]})" >&2
  exit 65
fi
exit $rc
