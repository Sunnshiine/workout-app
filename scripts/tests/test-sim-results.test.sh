#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

run() {
    rm -f "$root/seen" "$root/keyboard" "$root/load-read"
    STUB_LOG=$root/xcodebuild.log STUB_RC=${rc:-65} STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" "$@" >"$root/out" 2>"$root/err"
}
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}

printf '%s\n' "✘ Test seededSessionViewMatchesVisualBaseline() recorded an issue at SessionViewVisualTests.swift:11:32: Issue recorded" \
    "↳ Snapshot does not match reference." "✘ Test run with 30 tests in 8 suites failed after 4.437 seconds with 1 issue." \
    "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
STUB_SUMMARY='{"passedTests":29,"failedTests":1,"expectedFailures":0,"skippedTests":0}' run --no-build --sim "$sim" visual
bundle=$(sed -n 's/^bundle: //p' "$root/out")
expect "a run hands xcodebuild the bundle path it printed" "$(grep -A1 -x -- -resultBundlePath "$root/args" | tail -1)" "$bundle"
expect "a failed visual run names the snapshot diff command, then ends with its counts and bundle" "$(tail -2 "$root/out")" \
"snapshot diffs: scripts/snapshot-diffs.sh $bundle
test-sim: suite=visual passed=29 failed=1 expected=0 exit=65 load1=1.50/2.50 bundle=$bundle"

printf '%s\n' "✔ Test run with 30 tests in 8 suites passed after 4.437 seconds." "** TEST EXECUTE SUCCEEDED **" >"$root/xcodebuild.log"
rc=0 STUB_SUMMARY='{"passedTests":30,"failedTests":0,"expectedFailures":0}' run --no-build --sim "$sim" visual
expect "a passing visual run names no diff command" "$(grep -c '^snapshot diffs' "$root/out"; tail -1 "$root/out")" \
"0
test-sim: suite=visual passed=30 failed=0 expected=0 exit=0 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")"

printf '%s\n' "✘ Test parses() recorded an issue at ParserTests.swift:9:5: Expectation failed: isValid" \
    "✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 1 issue." "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
STUB_SUMMARY='{"passedTests":1019,"failedTests":1,"expectedFailures":0}' run --no-build --sim "$sim" unit WorkoutTrackerTests/ParserTests
expect "a failed run with no snapshot mismatch names no diff command" "$(tail -1 "$root/out"; grep -c '^snapshot diffs' "$root/out")" \
"test-sim: suite=unit,WorkoutTrackerTests/ParserTests passed=1019 failed=1 expected=0 exit=65 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")
0"

printf '%s\n' "━ Test run with 1069 tests in 11 suites passed after 4.453 seconds with 1 known issue." \
    "** TEST EXECUTE SUCCEEDED **" >"$root/xcodebuild.log"
rc=0 STUB_SUMMARY='{"passedTests":1068,"failedTests":0,"expectedFailures":1,"skippedTests":0}' run --no-build --sim "$sim" unit
expect "a test that records only a known issue counts as expected, not passed" "$(tail -1 "$root/out")" \
"test-sim: suite=unit passed=1068 failed=0 expected=1 exit=0 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")"

logs=$repo/.build/test-sim
finished="test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 load1=1.50/2.50 bundle=-"
fixture_run() {
    local stamp=$1 last_line=$2 age=$3
    mkdir "$logs/$stamp.xcresult" "$logs/$stamp-diffs"
    printf '%s\n' "◇ Test run started." "$last_line" >"$logs/$stamp-test.log"
    echo "** BUILD SUCCEEDED **" >"$logs/$stamp-build.log"
    touch -t "$age" "$logs/$stamp"*
}
minutes_ago() { date -v-"$1"M +%Y%m%d%H%M; }
rm -rf "$logs"
mkdir -p "$logs"
fixture_run 20991231-000001 "$finished" 202001010001
fixture_run 20991231-000002 "$finished" 202001010002
for n in 3 4 5 6; do fixture_run "20991231-00000$n" "$finished" "$(minutes_ago "$n")"; done
fixture_run 20991231-000007 "$finished" "$(minutes_ago 10)"
fixture_run 20991231-000008 "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "$(date -v-25H +%Y%m%d%H%M)"
fixture_run 20991231-000012 "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "$(date -v-2H +%Y%m%d%H%M)"
echo notes >"$logs/20200101-000000-notes.txt"
# Written now, so a match on the stamp alone would rank run 000001 among the five newest and keep it.
echo notes >"$logs/20991231-000001-notes.txt"
echo notes >"$logs/20991231-000002-notes.txt"
echo notes >"$logs/README.txt"
mkdir "$logs/unit.xcresult"
touch -t 202001010000 "$logs/20200101-000000-notes.txt" "$logs/20991231-000002-notes.txt" "$logs/README.txt" "$logs/unit.xcresult"
rc=0 STUB_STAMP=20991231-000000 STUB_SUMMARY='{"passedTests":1,"failedTests":0,"expectedFailures":0}' run --no-build --sim "$sim" unit
own=$(basename "$(sed -n 's/^bundle: //p' "$root/out")" .xcresult)
expect "a run deletes every file of a finished run older than the five written last, whatever their stamps sort as" \
    "$(tail -1 "$root/out" | sed 's/ load1=.*bundle=/ bundle=/'; ls "$logs")" \
"test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 bundle=$logs/$own.xcresult
20200101-000000-notes.txt
$own-test.log
$own.xcresult
20991231-000001-notes.txt
20991231-000002-notes.txt
20991231-000003-build.log
20991231-000003-diffs
20991231-000003-test.log
20991231-000003.xcresult
20991231-000004-build.log
20991231-000004-diffs
20991231-000004-test.log
20991231-000004.xcresult
20991231-000005-build.log
20991231-000005-diffs
20991231-000005-test.log
20991231-000005.xcresult
20991231-000006-build.log
20991231-000006-diffs
20991231-000006-test.log
20991231-000006.xcresult
20991231-000007-build.log
20991231-000007-diffs
20991231-000007-test.log
20991231-000007.xcresult
20991231-000012-build.log
20991231-000012-diffs
20991231-000012-test.log
20991231-000012.xcresult
README.txt
unit.xcresult"
expect "a run's test log ends with its result line" "$(tail -1 "$logs/$own-test.log")" \
    "test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 load1=1.50/2.50 bundle=$logs/$own.xcresult"
expect "a file whose name only starts with a stamp, even a deleted run's, and a file with no stamp, survive" \
    "$(cd "$logs" && ls -d 20200101-000000-notes.txt 20991231-000001-notes.txt 20991231-000002-notes.txt README.txt unit.xcresult)" \
"20200101-000000-notes.txt
20991231-000001-notes.txt
20991231-000002-notes.txt
README.txt
unit.xcresult"
expect "a run with no result line, untouched for 24 hours, is abandoned and deleted" \
    "$(cd "$logs" && ls -d 20991231-000008* 2>/dev/null)" ""
expect "a run with no result line touched 2 hours ago survives" "$(cd "$logs" && ls -d 20991231-000012*)" \
"20991231-000012-build.log
20991231-000012-diffs
20991231-000012-test.log
20991231-000012.xcresult"
expect "a finished run past the five written last survives while a file of it changed in the last 30 minutes" \
    "$(cd "$logs" && ls -d 20991231-000007*)" \
"20991231-000007-build.log
20991231-000007-diffs
20991231-000007-test.log
20991231-000007.xcresult"

printf '%s\n' "** BUILD FAILED **" >"$root/xcodebuild.log"
rm -rf "$logs"
STUB_STAMP=20991231-000009 run --sim "$sim" unit
expect "a run that fails in the build writes its result line to its test log" \
    "$(cat "$logs"/20991231-000009-*-test.log)" "$(result unit 65)"

build_failure() {
    printf '%s' "$2" >"$root/xcodebuild.log"
    rm -rf "$logs"
    rc=1 run --sim "$sim" unit
    local status=$?
    expect "$1" "$status|$(cat "$root/err")|$(tail -1 "$root/out")" \
        "65|${3:+$3$'\n'}build log: $(ls "$logs"/*-build.log)|$(result unit 65)"
}
build_failure "a build that fails with no output prints its log path and exits 65" "" ""
build_failure "a build that fails with no error: or BUILD FAILED line prints its log path and exits 65" \
"Command line invocation:
    xcodebuild build-for-testing
Killed: 9
" ""
build_failure "a build that fails with error lines prints them, then its log path, and exits 65" \
"Compiling
App/Foo.swift:1:1: error: cannot find 'bar' in scope
** BUILD FAILED **
" "App/Foo.swift:1:1: error: cannot find 'bar' in scope
** BUILD FAILED **"
many=$(for n in $(seq 20000); do echo "App/Foo$n.swift:1:1: error: cannot find 'bar' in scope"; done)
build_failure "a build with more error lines than it prints stops at 20, then prints its log path, and exits 65" \
"$many
** BUILD FAILED **
" "$(printf '%s\n' "$many" | sed -n 1,20p)"

printf '%s' "◇ Test run started." >"$root/xcodebuild.log"
STUB_STAMP=20991231-000010 run --no-build --sim "$sim" unit
expect "a result line lands on its own line after a log cut off mid-line" "$(tail -1 "$(sed -n 's/^log: //p' "$root/out")")" \
    "$(result unit 65)"

rm -rf "$logs"
printf '%s\n' "◇ Test run started." "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "** TEST EXECUTE SUCCEEDED **" \
    >"$root/xcodebuild.log"
STUB_RELEASE=$root/release STUB_STAMP=20991231-100000 STUB_SUMMARY='{"passedTests":1,"failedTests":0,"expectedFailures":0}' \
    STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/in-progress.out STUB_SEEN=$root/in-progress.seen \
    HOME=$root/home PATH="$root/bin:$PATH" \
    "$repo/scripts/test-sim.sh" --no-build --sim "$other_sim" unit >"$root/in-progress.out" 2>"$root/in-progress.err" &
pid=$!
for _ in $(seq 50); do [ -e "$root/in-progress.seen" ] && break; sleep 0.1; done
touch -t "$(date -v-2H +%Y%m%d%H%M)" "$logs/20991231-100000"*
for n in 1 2 3 4 5; do
    rc=0 STUB_STAMP=20991231-10000$n STUB_SUMMARY='{"passedTests":1,"failedTests":0,"expectedFailures":0}' run --no-build --sim "$sim" unit
done
touch "$root/release"
wait "$pid"
status=$?
own=$(basename "$(sed -n 's/^bundle: //p' "$root/in-progress.out")" .xcresult)
expect "a run still in xcodebuild survives five later runs in its checkout and ends with its bundle" \
    "$status $(tail -1 "$root/in-progress.out" | sed 's/ load1=.*bundle=/ bundle=/') $(cd "$logs" && ls -d 20991231-100000*)" \
    "0 test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 bundle=$logs/$own.xcresult $own-test.log
$own.xcresult"

rm -f "$root/release"
pids=()
for n in 1 2; do
    [ $n = 1 ] && udid=$sim || udid=$other_sim
    STUB_RELEASE=$root/release STUB_STAMP=20991231-200000 STUB_SUMMARY="{\"passedTests\":$n,\"failedTests\":0,\"expectedFailures\":0}" \
        STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/same-second-$n.out STUB_SEEN=$root/same-second-$n.seen \
        HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$udid" unit >"$root/same-second-$n.out" 2>"$root/same-second-$n.err" &
    pids+=($!)
done
for _ in $(seq 50); do [ -e "$root/same-second-1.seen" ] && [ -e "$root/same-second-2.seen" ] && break; sleep 0.1; done
touch "$root/release"
wait "${pids[@]}"
for n in 1 2; do
    out=$root/same-second-$n.out
    expect "run $n of two started in the same second reports its own counts and bundle in its output and its log" \
        "$(tail -1 "$out" | sed 's/ load1=.*bundle=/ bundle=/'; tail -1 "$(sed -n 's/^log: //p' "$out")" | sed 's/ load1=.*bundle=/ bundle=/')" \
        "test-sim: suite=unit passed=$n failed=0 expected=0 exit=0 bundle=$(sed -n 's/^bundle: //p' "$out")
test-sim: suite=unit passed=$n failed=0 expected=0 exit=0 bundle=$(sed -n 's/^bundle: //p' "$out")"
done
expect "two runs started in the same second get distinct log and bundle paths" \
    "$(grep -hE '^(log|bundle): ' "$root"/same-second-*.out | sort -u | wc -l | tr -d ' ')" 4

STUB_SUMMARY='not json' run --no-build --sim "$sim" unit
expect "an unreadable summary leaves the counts unknown" "$(tail -1 "$root/out")" \
"test-sim: suite=unit passed=- failed=- expected=- exit=65 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")"

run
status=$?
expect "a usage error exits 2 and still ends with the result line" "$status $(cat "$root/out")" "2 $(result - 2)"

for selection in ui all WorkoutTrackerUITests/WorkoutTrackerUISmokeTests; do
    run --no-build --sim "$sim" "$selection"
    expect "$selection runs the keyboard step once" \
        "$(cat "$root/keyboard"; grep '^keyboard: ' "$root/out")" "ensure $sim
keyboard: stub"
done
for selection in unit visual WorkoutTrackerSnapshotTests/BlockGridVisualTests; do
    run --no-build --sim "$sim" "$selection"
    expect "$selection skips the keyboard step" "$([ -e "$root/keyboard" ] && echo ran || echo skipped)" skipped
done

run --no-build unit --sim
status=$?
expect "a --sim with no UDID is a usage error, not a clean run" "$status $(cat "$root/out")" "2 $(result unit 2)"

rm -f "$root/seen" "$root/load-read"
printf '%s\n' "◇ Test run started." >"$root/xcodebuild.log"
STUB_SLEEP=2 HOME=$root/home PATH="$root/bin:$PATH" STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/out STUB_SEEN=$root/seen \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err" &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$root/seen" ] && break; sleep 0.2; done
kill -TERM "$pid"
wait "$pid"
status=$?
expect "a run killed with TERM reports exit=143, not the last command's 0" "$status $(tail -1 "$root/out" | sed 's/ load1=.*//')" \
    "143 test-sim: suite=unit passed=- failed=- expected=- exit=143"

STUB_KEYBOARD_RC=70 run --no-build --sim "$sim" ui
status=$?
expect "a keyboard step that fails stops the run before xcodebuild with its status" \
    "$status $([ -e "$root/seen" ] && echo xcodebuild-ran || echo xcodebuild-skipped) $(tail -1 "$root/out")" \
    "70 xcodebuild-skipped $(result ui 70)"

STUB_BACKDATE=/tmp/workout-verify-$sim/lock run --no-build --sim "$sim" unit
expect "a run's end restarts its simulator's idle clock, however long ago it took the lock" \
    "$(python3 -c 'import os, sys, time; print(int((time.time() - os.stat(sys.argv[1]).st_mtime) // 60))' "/tmp/workout-verify-$sim/lock")" 0

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
