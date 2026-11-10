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
first three issues each test recorded with the values each one compared, every failing test, the
open issue whose title names each failing test, and any error or crash that stopped xcodebuild
before the run finished.
The simulator comes from Simlock (.agents/skills/simlock/SKILL.md): an iPhone 17 Pro on iOS 27.0,
leased for this run alone and released when the script exits, even under SIGKILL. --sim UDID (or
SIM=UDID) runs on the simulator of a lease you already hold instead, and refuses (exit 2) any other
UDID. Exits 78 when simlock is not on PATH. Refuses (exit 75) while another test-sim.sh run holds
the simulator, or a verify run whose app on it was used in the last WORKOUT_LEASE_MINUTES (60), or
when your Simlock identity already holds a lease and no --sim names it. Waits while the host is busy,
saying why once a minute: in Simlock's queue for a simulator, while free memory
(kern.memorystatus_level, percent) is under WORKOUT_MEM_FLOOR (25; 0 turns it off), and to build
while free disk on the checkout's or HOME's volume is under WORKOUT_DISK_FLOOR (5120 MB; 0 turns it
off). Gives up with exit 75 after WORKOUT_ADMIT_WAIT seconds (540) in either wait. The build alone
runs in a host-wide hostgate slot (scripts/build-slot.sh --help), which can wait too and exit 75;
the test run takes none.
A selection that includes WorkoutTrackerUITests first runs scripts/sim-keyboard.sh ensure, which
turns off the keyboard preference that hides the software keyboard and prints one `keyboard:` line.
Every test run writes a result bundle and prints its path. A run's files in .build/test-sim are
<stamp>-build.log, <stamp>-test.log, <stamp>.xcresult, and <stamp>-diffs, and its test log ends
with its result line. Each run keeps the five runs written last and deletes an older run's files
when its test log ends with a result line and none of them changed in the last 30 minutes, or
when none of them changed in the last 24 hours, as for a run killed before its result line
(SIGKILL, power loss). Copy a bundle or diff you cite into your proof directory, since only five
runs are kept.
Exits 65 when the build fails, after printing up to 20 of its error lines, then `build log: <path>`,
on stderr.
Exits 69 when xcodebuild failed and its log shows a simulator fault rather than a test result, such as
a launch that returned no process handle, a CoreSimulator SimError, or a test the simulator's
shutdown killed with SIGTERM, or when Simlock took the lease back mid-run. It shuts the simulator
down first, so a rerun gets a fresh one.
When a snapshot does not match its reference, scripts/snapshot-diffs.sh <bundle> lists the
reference, failure, and difference images.
The last line, on every exit after this usage text, is
  test-sim: suite=<s> passed=<n> failed=<m> expected=<k> exit=<e> load1=<start>/<end> bundle=<path>
where expected= counts tests whose only issues were known issues, which passed= leaves out, exit= is
this script's exit status, `-` means unknown, and load1 is the 1-minute load average.
Each XCTest test gets WORKOUT_TEST_ALLOWANCE seconds (60), or up to WORKOUT_TEST_MAX_ALLOWANCE (300)
when it asks for more (xcodebuild's -test-timeouts-enabled). Exits 124 when the whole test run
outlives WORKOUT_TEST_RUN_LIMIT seconds (3600), after stopping it, so a run that stops making
progress cannot hold its simulator for good.
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
  [ -z "${run_pid:-}" ] || kill -TERM "$run_pid" 2>/dev/null
  end_lease
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
host_knob WORKOUT_TEST_ALLOWANCE 60 1
host_knob WORKOUT_TEST_MAX_ALLOWANCE 300 1
host_knob WORKOUT_TEST_RUN_LIMIT 3600 1
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

claim_sim "$sim" "test-sim.sh run" "$build"
[ $ui = 0 ] || "$repo/scripts/sim-keyboard.sh" ensure "$sim"
destination="platform=iOS Simulator,id=$sim"

logs=$repo/.build/test-sim
mkdir -p "$logs"
stamp=$(date +%Y%m%d-%H%M%S)-$$

if [ $build = 1 ]; then
  rc=0
  with_build_slot --log "$logs/$stamp-build.log" xcodebuild build-for-testing -project "$project" -scheme WorkoutTracker \
    -destination "$destination" -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO || rc=$?
  [ $rc != 75 ] || [ -e "$logs/$stamp-build.log" ] || exit 75
  [ $rc = 0 ] || { grep -m 20 -E "error:|BUILD FAILED" "$logs/$stamp-build.log" >&2 || true; echo "build log: $logs/$stamp-build.log" >&2; exit 65; }
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
  -test-timeouts-enabled YES -default-test-execution-time-allowance "$WORKOUT_TEST_ALLOWANCE" \
  -maximum-test-execution-time-allowance "$WORKOUT_TEST_MAX_ALLOWANCE" \
  -collect-test-diagnostics never -resultBundlePath "$bundle" CODE_SIGNING_ALLOWED=NO "${targets[@]}" > "$log" 2>&1 7>&- 8>&- 9>&- &
run_pid=$!
# A run that never ends holds its simulator for good, as xcodebuild idling after its last test did.
perl -e 'sleep $ARGV[0]; exit 0 unless kill 0, $ARGV[1]; open my $f, ">", $ARGV[2]; kill "TERM", $ARGV[1]' \
  "$WORKOUT_TEST_RUN_LIMIT" "$run_pid" "$log.overran" 7>&- 8>&- 9>&- &
watchdog=$!
wait "$run_pid"
rc=$?
run_pid=
kill "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null
if [ -e "$log.overran" ]; then
  rm -f "$log.overran"
  echo "the test run outlived WORKOUT_TEST_RUN_LIMIT ($WORKOUT_TEST_RUN_LIMIT s), so it was stopped; the log's last lines show where it stood: $log" >&2
  exit 124
fi
# What xcodebuild prints when CoreSimulator or the test runner breaks rather than the app (#537, #908).
# "Early unexpected exit" only from the XCTest runner; the app crashing at launch prints it too.
fault=$([ $rc = 0 ] || grep -m1 -oE 'did not return a process handle nor launch error|Simulator device failed to launch|com\.apple\.CoreSimulator\.SimError|The test runner failed to initialize for UI testing|Lost connection to testmanagerd|-Runner \([0-9]+\) encountered an error \(Early unexpected exit' "$log") || true
# A simulator that shuts down mid-run SIGTERMs the app; xcodebuild restarts past it, and only the
# result bundle names the signal. An app's own crash is abrt, segv, trap or kill.
[ $rc = 0 ] || [ -n "$fault" ] || fault=$(xcrun xcresulttool get test-results tests --path "$bundle" --compact 2>/dev/null \
  | grep -m1 -o 'Test crashed with signal term') || true
ls -t "$logs" | sed -nE 's/^([0-9]{8}-[0-9]{6}(-[0-9]+)?)(-build\.log|-test\.log|\.xcresult|-diffs)$/\1/p' \
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
if [ -n "$fault" ]; then
  simlock simctl shutdown "$sim" >/dev/null 2>&1 || true
  echo "simulator fault, not a test result: xcodebuild reported \"$fault\". Shut $sim down so the next run boots it fresh; rerun the same command, and if it faults again, release its Simlock lease and lease another" >&2
  rc=69
fi
lease_kept
if ! "$repo/scripts/test-log-summary.sh" "$log"; then
  [ $rc = 0 ] || { echo "xcodebuild exited $rc before the test run finished; the lines above and the log say why" >&2; exit $rc; }
  echo "no tests ran; check the selection (${targets[*]})" >&2
  exit 65
fi
exit $rc
