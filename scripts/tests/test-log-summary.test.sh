#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$repo/Tests/Unit" "$repo/Tests/Component" "$root/bin"
cp "$script_dir/../test-log-summary.sh" "$script_dir/../test-log-summary.awk" "$repo/scripts/"
touch "$repo/Tests/Unit/SyncCoordinatorTests.swift" "$repo/Tests/Unit/ProbeTests.swift" "$repo/Tests/Component/ProbeTests.swift"
git -C "$repo" init -q && git -C "$repo" add -A
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_ARGS"
printf '978\tsyncLaunchesTheExerciseHistoryFillWithoutWaitingForIt exceeds its 60 s time limit\n'
printf '627\tUI test testDeveloperToolsRouteLoadsFromSettings intermittently times out at 84 s\n'
printf '700\tgrowsFast drops a row\n'
printf '701\tgrows: the envelope clips under Dynamic Type\n'
printf '702\t"Every cell of the RPE Table matches the published RTS chart" misreads RPE 6.5\n'
STUB
chmod +x "$root/bin/gh"

check() {
    local name=$1 want_status=$2 want=$3 log=$4 actions=${5:-}
    printf '%s\n' "$log" >"$root/test.log"
    GITHUB_ACTIONS=$actions STUB_ARGS=$root/args PATH="$root/bin:$PATH" \
        "$repo/scripts/test-log-summary.sh" "$root/test.log" >"$root/out" 2>&1
    local status=$? got
    got=$(cat "$root/out")
    if [ "$status" = "$want_status" ] && [ "$got" = "$want" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    got:\n%s\n    want:\n%s\n' "$got" "$want"
    fi
}

check "each failing test names the open issue whose title holds its name as a word" 0 \
"✘ Test grows(height:) recorded an issue with 1 argument height → 70 at GrowSuite.swift:19:9: Expectation failed
✘ Test \"Every cell of the RPE Table matches the published RTS chart\" with 12 test cases failed after 0.004 seconds with 3 issues.
✘ Test run with 3 tests in 2 suites failed after 0.100 seconds with 4 issues.
Failing tests:
	-[SomeSuite grows(height:)]
	WorkoutTrackerUISmokeTests.testDeveloperToolsRouteLoadsFromSettings()
open issue #701: grows: the envelope clips under Dynamic Type
open issue #702: \"Every cell of the RPE Table matches the published RTS chart\" misreads RPE 6.5
open issue #627: UI test testDeveloperToolsRouteLoadsFromSettings intermittently times out at 84 s" \
"◇ Test run started.
✘ Test grows(height:) recorded an issue with 1 argument height → 70 at GrowSuite.swift:19:9: Expectation failed
✘ Test \"Every cell of the RPE Table matches the published RTS chart\" with 12 test cases failed after 0.004 seconds with 3 issues.
✘ Test run with 3 tests in 2 suites failed after 0.100 seconds with 4 issues.
Failing tests:
	-[SomeSuite grows(height:)]
	WorkoutTrackerUISmokeTests.testDeveloperToolsRouteLoadsFromSettings()"
if [ "$(cat "$root/args")" = "issue list --state open --limit 1000 --json number,title --jq .[] | \"\(.number)\t\(.title)\"" ]; then
    ok "the lookup asks gh for every open issue's number and title"
else
    bad "the lookup asks gh for every open issue's number and title: gh got $(cat "$root/args")"
fi

rm -f "$root/args"
check "a passing run asks gh nothing" 0 \
"━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue." \
"━ Test replanningWhenTheRefetchFails() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue."
if [ -e "$root/args" ]; then bad "gh ran for a passing run"; else ok "gh did not run for a passing run"; fi

check "in GitHub Actions each recorded issue annotates its file, its expectation, and its open issue" 0 \
"✘ Test syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() recorded an issue at SyncCoordinatorTests.swift:192:5: Expectation failed: 1 + 1 == 3
↳ scratch: fails on purpose
↳   1 + 1 → 2
✘ Test probe() recorded an issue at ProbeTests.swift:5:5: Expectation failed: sets % 2 == 1
✘ Test run with 2 tests in 2 suites failed after 0.100 seconds with 2 issues.
open issue #978: syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt exceeds its 60 s time limit
no open issue names probe
::error file=Tests/Unit/SyncCoordinatorTests.swift,line=192,col=5,title=syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt failed::Expectation failed: 1 + 1 == 3%0Ascratch: fails on purpose%0A  1 + 1 → 2%0Aopen issue #978: syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt exceeds its 60 s time limit
::error line=5,col=5,title=probe failed::Expectation failed: sets %25 2 == 1" \
"✘ Test syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() recorded an issue at SyncCoordinatorTests.swift:192:5: Expectation failed: 1 + 1 == 3
↳ scratch: fails on purpose
↳ 1 + 1 == 3 → false
↳   1 + 1 → 2
✘ Test probe() recorded an issue at ProbeTests.swift:5:5: Expectation failed: sets % 2 == 1
↳ sets % 2 == 1 → false
✘ Test run with 2 tests in 2 suites failed after 0.100 seconds with 2 issues." true

check "a log where no test ran exits 1 and still looks up its failing test" 1 \
"Failing tests:
	AtmosphereVisualTests.livingPaperMatchesVisualBaseline()
** TEST EXECUTE FAILED **
no open issue names livingPaperMatchesVisualBaseline" \
"◇ Test livingPaperMatchesVisualBaseline() started.
Failing tests:
	AtmosphereVisualTests.livingPaperMatchesVisualBaseline()

** TEST EXECUTE FAILED **"

check "a line that only quotes XCTest's summary is not a test run" 1 \
"✔ Test run with 0 tests in 0 suites passed after 0.001 seconds." \
"◇ Test run started.
[sync] Executed 3 tests, with 0 failures (0 unexpected) in 0.100 (0.100) seconds
    Executed 2 tests, with 0 failures (0 unexpected) in 0.100 (0.100) seconds
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds."

check "a crash after a failing test prints the crash too" 1 \
"✘ Test probe() recorded an issue at ProbeTests.swift:5:5: Expectation failed: sets % 2 == 1
Tests/Unit/ProbeTests.swift:9: Fatal error: Index out of range
💣 Program crashed: System trap at 0x0000000100f2c1a4
error: Exited with unexpected signal code 5
no open issue names probe" \
"◇ Test run started.
✘ Test probe() recorded an issue at ProbeTests.swift:5:5: Expectation failed: sets % 2 == 1
Tests/Unit/ProbeTests.swift:9: Fatal error: Index out of range
💣 Program crashed: System trap at 0x0000000100f2c1a4
error: Exited with unexpected signal code 5"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
