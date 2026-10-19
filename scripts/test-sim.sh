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
Builds the app and only the selected test targets once with build-for-testing, then runs every
requested suite in one test-without-building session from that build's xctestrun file. The build
uses test-sim.xcscheme, a copy of the WorkoutTracker scheme that keeps only the selected test
targets, written under WorkoutTracker.xcodeproj/xcuserdata. --no-build reuses the last build when
it covered every selected test target, and otherwise exits 65 naming the targets it covered.
Prints the test log path before the run starts. The summary at the end holds the run counts, the
first three issues each test recorded with the values each one compared, every failing test, and
any error or crash that stopped xcodebuild before the run finished.
The simulator is the booted iPhone 17 Pro, else the newest available one, which the script boots.
With no available iPhone 17 Pro it creates one on iOS 27.0 (scripts/ensure-simulator.sh) and boots that.
Refuses (exit 75) while another test-sim.sh run holds that simulator, or a verify run whose app
on it was used in the last WORKOUT_LEASE_MINUTES (60); a verify run idle for longer is reclaimed
and its app stopped. Refuses (exit 2) a --sim UDID that simctl lists no available simulator for.
Waits while the host is busy, saying why once a minute: while free memory (kern.memorystatus_level,
percent) is under WORKOUT_MEM_FLOOR (25; 0 turns it off), to boot while WORKOUT_SIM_CAP (10) other
simulators are booted, and to build while all WORKOUT_BUILD_SLOTS (2) host-wide build slots are
taken. Gives up with exit 75 after WORKOUT_ADMIT_WAIT seconds (540), a budget that restarts each time
a build slot changes hands. At the cap, a boot first shuts
down the least recently used booted workout-lane-* simulator that no run holds, that runs no app
but a verify app past its lease, and whose last claim ended WORKOUT_IDLE_MINUTES (2) or more ago,
and says so on stderr.
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
shutdown killed with SIGTERM. It shuts the simulator down
first, so rerunning the same command boots it fresh.
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
  [ -z "${claimed_sim:-}" ] || end_claim
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
. "$repo/scripts/compile-cache.sh"
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
test_targets=$(printf '%s\n' "${targets[@]#-only-testing:}" | cut -d/ -f1 | awk '!seen[$0]++' | tr '\n' ' ')

picked=$(pick_sim "$sim" create)
read -r sim state <<< "$picked"
[ "$state" != named ] || sim_available "$sim" || exit
claim_sim "$sim" "test-sim.sh run" "$build"
[ $ui = 0 ] || "$repo/scripts/sim-keyboard.sh" ensure "$sim"
destination="platform=iOS Simulator,id=$sim"

logs=$repo/.build/test-sim
mkdir -p "$logs"
stamp=$(date +%Y%m%d-%H%M%S)-$$

if [ $build = 1 ]; then
  # build-for-testing builds every test target its scheme lists, whatever -only-testing says.
  schemes=$project/xcuserdata/$(id -un).xcuserdatad/xcschemes
  mkdir -p "$schemes"
  awk -v keep="$test_targets" '
    BEGIN { n = split(keep, names, " "); for (i = 1; i <= n; i++) wanted[names[i]] = 1 }
    /<TestableReference/ { ref = ""; inref = 1 }
    inref {
      ref = ref $0 "\n"
      if (match($0, /BlueprintName = "[^"]*"/)) name = substr($0, RSTART + 17, RLENGTH - 18)
      if (/<\/TestableReference>/) { inref = 0; if (name in wanted) { printf "%s", ref; delete wanted[name] } }
      next
    }
    { print }
    END { for (name in wanted) { print "no test target " name " in the WorkoutTracker scheme" > "/dev/stderr"; bad = 1 }; exit bad }
  ' "$project/xcshareddata/xcschemes/WorkoutTracker.xcscheme" > "$schemes/test-sim.xcscheme" || exit 2
  with_build_slot xcodebuild build-for-testing -project "$project" -scheme test-sim -destination "$destination" \
    -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO ${compile_cache_settings[@]+"${compile_cache_settings[@]}"} \
    > "$logs/$stamp-build.log" 2>&1 \
    || { grep -m 20 -E "error:|BUILD FAILED" "$logs/$stamp-build.log" >&2 || true; echo "build log: $logs/$stamp-build.log" >&2; exit 65; }
fi

xctestrun=$(for plist in ~/Library/Developer/Xcode/DerivedData/WorkoutTracker-*/info.plist; do
  if [ "$(plutil -extract WorkspacePath raw "$plist")" = "$project" ]; then
    ls -t "$(dirname "$plist")"/Build/Products/test-sim_iphonesimulator*.xctestrun 2>/dev/null
  fi
done | head -1) || true
[ -n "$xctestrun" ] || { echo "no xctestrun for $project; run without --no-build" >&2; exit 65; }
covered=$(awk '/<key>BlueprintName<\/key>/ { getline; gsub(/.*<string>|<\/string>.*/, ""); print }' "$xctestrun" | tr '\n' ' ')
for name in $test_targets; do
  case " $covered" in *" $name "*) ;; *)
    echo "the last build covered ${covered:-no test target }but not $name; run without --no-build" >&2
    exit 65 ;;
  esac
done

log=$logs/$stamp-test.log
echo "log: $log"
bundle=$logs/$stamp.xcresult
echo "bundle: $bundle"
set +e
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
  -collect-test-diagnostics never -resultBundlePath "$bundle" CODE_SIGNING_ALLOWED=NO "${targets[@]}" > "$log" 2>&1
rc=$?
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
  xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
  echo "simulator fault, not a test result: xcodebuild reported \"$fault\". Shut $sim down so the next run boots it fresh; rerun the same command, and if it faults again, run xcrun simctl erase $sim first" >&2
  rc=69
fi
if ! awk -f "$repo/scripts/test-log-summary.awk" "$log" | uniq; then
  [ $rc = 0 ] || { echo "xcodebuild exited $rc before the test run finished; the lines above and the log say why" >&2; exit $rc; }
  echo "no tests ran; check the selection (${targets[*]})" >&2
  exit 65
fi
exit $rc
