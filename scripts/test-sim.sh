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
A selection that includes WorkoutTrackerUITests first runs scripts/sim-keyboard.sh ensure, which
turns off the keyboard preference that hides the software keyboard and prints one `keyboard:` line.
Every test run writes a result bundle and prints its path. A run's files in .build/test-sim are
<stamp>-build.log, <stamp>-test.log, <stamp>.xcresult, and <stamp>-diffs, and its test log ends
with its result line. Each run keeps the five runs written last and deletes an older run's files
when its test log ends with a result line and none of them changed in the last 30 minutes, or
when none of them changed in the last 24 hours, as for a run killed before its result line
(SIGKILL, power loss). Copy a bundle or diff you cite into your proof directory, since only five
runs are kept.
When a snapshot does not match its reference, scripts/snapshot-diffs.sh <bundle> lists the
reference, failure, and difference images.
The last line, on every exit after this usage text, is
  test-sim: suite=<s> passed=<n> failed=<m> expected=<k> exit=<e> load1=<start>/<end> bundle=<path>
where expected= counts tests whose only issues were known issues, which passed= leaves out, exit= is
this script's exit status, `-` means unknown, and load1 is the 1-minute load average.
A pipe such as `| tee` hides the exit status from the caller; read exit= instead.
EOF
  exit 2
}

load1() { sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo -; }

finish() {
  local rc=$? counts="- - -" passed failed expected shown=- result
  if [ -n "$bundle" ] && [ -d "$bundle" ]; then
    shown=$bundle
    counts=$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null | python3 -c '
import json, sys
s = json.load(sys.stdin)
print(s["passedTests"], s["failedTests"], s["expectedFailures"])' 2>/dev/null) || counts="- - -"
    grep -q 'does not match reference' "$log" 2>/dev/null && echo "snapshot diffs: scripts/snapshot-diffs.sh $bundle"
  fi
  read -r passed failed expected <<< "$counts"
  result="test-sim: suite=${suite:--} passed=$passed failed=$failed expected=$expected exit=$rc load1=$load_start/$(load1) bundle=$shown"
  if [ -n "$stamp" ]; then
    {
      [ -z "$(tail -c 1 "$logs/$stamp-test.log")" ] || echo
      echo "$result"
    } 2>/dev/null >>"$logs/$stamp-test.log" || true
  fi
  echo "$result"
  exit "$rc"
}

load_start=$(load1)
suite=
bundle=
stamp=
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

repo=$(cd "$(dirname "$0")/.." && pwd)
. "$repo/scripts/sim-lock.sh"
project=$repo/WorkoutTracker.xcodeproj
build=1
sim=${SIM:-}
targets=()
ui=0

while [ $# -gt 0 ]; do
  case $1 in -*) ;; *) suite=${suite:+$suite,}$1 ;; esac
  case $1 in
    --no-build) build=0 ;;
    --sim) [ $# -ge 2 ] || usage; sim=$2; shift ;;
    -*) usage ;;
    unit) targets+=(-only-testing:WorkoutTrackerTests) ;;
    visual) targets+=(-only-testing:WorkoutTrackerSnapshotTests) ;;
    ui) targets+=(-only-testing:WorkoutTrackerUITests); ui=1 ;;
    all) targets+=(-only-testing:WorkoutTrackerTests -only-testing:WorkoutTrackerSnapshotTests -only-testing:WorkoutTrackerUITests); ui=1 ;;
    WorkoutTrackerUITests*) targets+=("-only-testing:$1"); ui=1 ;;
    *) targets+=("-only-testing:$1") ;;
  esac
  shift
done
[ ${#targets[@]} -gt 0 ] || usage

picked=$(pick_sim "$sim" create)
read -r sim state <<< "$picked"
[ "$state" != named ] || sim_available "$sim" || exit
[ "$state" != Shutdown ] || xcrun simctl boot "$sim"
claim_sim "$sim" "test-sim.sh run"
[ $ui = 0 ] || "$repo/scripts/sim-keyboard.sh" ensure "$sim"
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
bundle=$logs/$stamp.xcresult
echo "bundle: $bundle"
set +e
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
  -collect-test-diagnostics never -resultBundlePath "$bundle" CODE_SIGNING_ALLOWED=NO "${targets[@]}" > "$log" 2>&1
rc=$?
ls -t "$logs" | sed -nE 's/^([0-9]{8}-[0-9]{6})(-build\.log|-test\.log|\.xcresult|-diffs)$/\1/p' \
  | awk '!seen[$0]++' | tail -n +6 | while IFS= read -r old; do
    files=()
    for file in "$logs/$old-build.log" "$logs/$old-test.log" "$logs/$old.xcresult" "$logs/$old-diffs"; do
      [ ! -e "$file" ] || files+=("$file")
    done
    case $(tail -n 1 "$logs/$old-test.log" 2>/dev/null) in
      "test-sim: "*) quiet=30 ;;
      *) quiet=1440 ;;
    esac
    [ -z "$(find "${files[@]}" -maxdepth 0 -mmin -$quiet)" ] && rm -rf "${files[@]}"
  done
set -e
if ! awk -f "$repo/scripts/test-log-summary.awk" "$log" | uniq; then
  [ $rc = 0 ] || { echo "xcodebuild exited $rc before the test run finished; the lines above and the log say why" >&2; exit $rc; }
  echo "no tests ran; check the selection (${targets[*]})" >&2
  exit 65
fi
exit $rc
