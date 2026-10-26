#!/bin/bash
# shellcheck disable=SC2016  # stub and expected text hold literal $
set -uo pipefail

# shellcheck source=scripts/tests/mutate-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/mutate-harness.sh"

caller_state() { git -C "$repo" status --porcelain; shasum "$repo"/Sources/Gate/*; }

killed_row="killed       Sources/Gate/Gate.swift:2  sed      2s/>= 3/> 3/  GateTests.testOpensAtFour +1"
survived_row="SURVIVED     Sources/Gate/Gate.swift:5  sed      5s/10/11/"

rm -f "$STUB_WATCH"
mutate --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/' '5s/10/11/'
expect "a killed and a surviving mutant print one row each and exit 1" "$status
$out" "1
scratch: $pool/1 at $(git -C "$repo" rev-parse --short=8 HEAD)
baseline: passed 2 tests (swift test --filter GateTests)
$killed_row
$survived_row
2 mutants: 1 killed, 1 SURVIVED"
expect "the log dir sits under the caller's .build/mutate and lists every killer" \
    "${logdir%/*} $(cat "$logdir/results.tsv")" "$repo/.build/mutate m1	killed	GateTests.testOpensAtFour; gateOpensAtThree
m2	SURVIVED	"

mutate --filter GateTests Sources/Gate/Gate.swift 's/10/11/' '2s/>= 3/> 3/'
expect "a pattern-addressed mutant that survives prints its row, and the run goes on to the next (#898)" "$status
$(sed 1,2d <<<"$out")" "1
SURVIVED     Sources/Gate/Gate.swift:-  sed      s/10/11/
killed       Sources/Gate/Gate.swift:2  sed      2s/>= 3/> 3/  GateTests.testOpensAtFour +1
2 mutants: 1 killed, 1 SURVIVED"

echo 'let extraOn = true' >"$repo/Sources/Gate/Extra.swift"
sed -i '' 's/gateLimit = 10/gateLimit = 12/' "$repo/Sources/Gate/Gate.swift"
before=$(caller_state)
rm -f "$STUB_WATCH"
mutate Sources/Gate/Extra.swift '1s/true/false/'
expect "an untracked caller file is mutated in the slot" "$status
$out" "1
scratch: $pool/1 at $(git -C "$repo" rev-parse --short=8 HEAD) + your uncommitted changes
baseline: passed 3 tests (swift test)
SURVIVED     Sources/Gate/Extra.swift:1  sed      1s/true/false/
1 mutant: 1 SURVIVED"
expect "the slot builds the caller's uncommitted edit" "$(grep '^slot line 5' "$STUB_WATCH" | sort -u)" \
    "slot line 5: let gateLimit = 12"
expect "the caller's status and bytes never change while mutants run" \
    "$(grep -v '^slot line 5' "$STUB_WATCH" | sort -u)" "$(printf '%s\n' "$before" "$before" | sort -u)"
expect "the caller's uncommitted edits are still there after the run" "$(caller_state)" "$before"
git -C "$repo" checkout -q -- Sources/Gate/Gate.swift && rm "$repo/Sources/Gate/Extra.swift"

sed -i '' 's/count >= 3/count > 3/' "$repo/Sources/Gate/Gate.swift"
mutate --filter Gate Sources/Gate/Gate.swift '5s/10/11/'
expect "a failing baseline exits 2 naming each failure and prints no mutant row" "$status
$out
$err" "2
scratch: $pool/1 at $(git -C "$repo" rev-parse --short=8 HEAD) + your uncommitted changes
the untouched snapshot must pass before mutating; swift test --filter Gate reports:
  failed: GateTests.testOpensAtFour
  failed: gateOpensAtThree
  log: $logdir/baseline.log"
git -C "$repo" checkout -q -- Sources/Gate/Gate.swift

mutate --filter Gate Sources/Gate/Gate.swift '9s/x/y/'
expect "an expression that changes nothing exits 2 before any build" "$status
$out
$err" "2

'9s/x/y/' changed nothing in Sources/Gate/Gate.swift; check its address"

mutate --filter Gate Sources/Gate/Gate.swift '2s/count/BREAK/'
expect "a hand-written mutant that does not build is nocompile and exits 1" "$status
$(tail -2 <<<"$out")" "1
nocompile    Sources/Gate/Gate.swift:2  sed      2s/count/BREAK/  Sources/Gate/Gate.swift:2:5: error: cannot find 'BREAK' in scope
1 mutant: 1 nocompile"

mutate --filter GateTests Sources/Gate/Gate.swift '5s/10/CRASH_IN_TEST/' '5s/10/CRASH/'
expect "a mutant that crashes the test process is killed, by the one test it was running if any" "$status
$(tail -3 <<<"$out")" "0
killed       Sources/Gate/Gate.swift:5  sed      5s/10/CRASH_IN_TEST/  limitHolds (crashed)
killed       Sources/Gate/Gate.swift:5  sed      5s/10/CRASH/          (test process crashed)
2 mutants: 2 killed"

mutate --filter GateTests Sources/Gate/Gate.swift '5s/10/EXPLODE/'
expect "an error row is one short line without toolchain paths, and results.tsv keeps the whole reason" "$status
$(tail -2 <<<"$out")
$(grep -c "/Applications/Xcode.app/Contents/Developer/Toolchains" "$logdir/results.tsv")" "1
error        Sources/Gate/Gate.swift:5  sed      5s/10/EXPLODE/  exit 1: error: Process 'swiftpm-testing-helper --test-bundle-path WorkoutTrackerTests --testing-library swift-testing...
1 mutant: 1 error
1"

rm -f "$root/hang.pid"
set -m
(cd "$repo" && exec scripts/mutate.sh --filter GateTests Sources/Gate/Gate.swift '5s/10/HANG/') >/dev/null 2>&1 &
group=$!
set +m
wait_for "$root/hang.pid"
kill -KILL -- -"$group"
wait "$group" 2>/dev/null
for _ in $(seq 1 40); do lsof "$locks/1.lock" >/dev/null 2>&1 || kill -0 "$(cat "$root/hang.pid")" 2>/dev/null || break; sleep 0.05; done
expect "a SIGKILL to mutate.sh's process group kills the test it started, in its own process group, and frees the slot within a second" "$(
    if kill -0 "$(cat "$root/hang.pid")" 2>/dev/null; then echo "the hung test still runs"; else echo "the hung test is gone"; fi
    lsof -t "$locks/1.lock" 2>/dev/null | wc -l | tr -d ' ')" "the hung test is gone
0"

MUTATE_TIMEOUT=2 mutate --filter GateTests Sources/Gate/Gate.swift '5s/10/HANG/'
expect "a mutant that runs past MUTATE_TIMEOUT is killed with its whole session, test process group included" "$status
$(tail -2 <<<"$out")
$(if kill -0 "$(cat "$root/hang.pid")" 2>/dev/null; then echo "the hung test still runs"; else echo "the hung test is gone"; fi)" "0
killed       Sources/Gate/Gate.swift:5  sed      5s/10/HANG/  timed out after 2s
1 mutant: 1 killed
the hung test is gone"

printf '%s\n' '#if canImport(UIKit)' 'let platformLimit = 4' '#endif' >"$repo/Sources/Gate/Platform.swift"
mutate --filter GateTests Sources/Gate/Platform.swift '2s/4/5/'
expect "a surviving mutant on a line this build compiles out is unreachable" "$status
$(tail -2 <<<"$out")
$(cat "$logdir/results.tsv")" "1
unreachable  Sources/Gate/Platform.swift:2  sed      2s/4/5/  compiled out of this build (#if or no target)
1 mutant: 1 unreachable
m1	unreachable	compiled out of this build (#if or no target)"
mutate --filter GateTests Sources/Gate/Platform.swift 's/4/5/'
expect "the reach probe finds a pattern-addressed mutant's line by comparing the files" "$status
$(tail -2 <<<"$out")" "1
unreachable  Sources/Gate/Platform.swift:-  sed      s/4/5/  compiled out of this build (#if or no target)
1 mutant: 1 unreachable"
rm "$repo/Sources/Gate/Platform.swift"

rm -f "$STUB_CALLS"
STUB_FLAKY_FROM=2 mutate Sources/Gate/Gate.swift '2s/>= 3/> 3/' '5s/10/11/'
expect "a kill whose every killer also fails on the untouched snapshot is flaky, after one recheck" "$status
$(sed 1d <<<"$out")
$(cat "$logdir/results.tsv")
$(cat "$STUB_CALLS")" "1
baseline: passed 3 tests (swift test)
killed       Sources/Gate/Gate.swift:2  sed      2s/>= 3/> 3/  GateTests.testOpensAtFour +2
killed       Sources/Gate/Gate.swift:5  sed      5s/10/11/     nameIsGate
recheck: the untouched snapshot fails nameIsGate
flaky        Sources/Gate/Gate.swift:5  sed      5s/10/11/     nameIsGate
2 mutants: 1 killed, 1 flaky
m1	killed	GateTests.testOpensAtFour; gateOpensAtThree; nameIsGate
m2	flaky	nameIsGate
4"

touch "$root/gate1"
(cd "$repo" && exec env STUB_GATE="$root/gate1" scripts/mutate.sh --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/' >"$root/out1" 2>&1) &
first=$!
wait_for "$root/gate1.reached"
(cd "$repo" && scripts/mutate.sh --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/' >"$root/out2" 2>&1)
second=$?
rm "$root/gate1"
wait $first
expect "a run while another holds slot 1 takes slot 2, and both kill the mutant" \
    "$? $second $(grep -h '^scratch:' "$root/out1" "$root/out2" | cut -d' ' -f2 | tr '\n' ' ')$(grep -c '^killed' "$root/out1" "$root/out2" | tr '\n' ' ')" \
    "0 0 $pool/1 $pool/2 $root/out1:1 $root/out2:1 "

touch "$root/gate2"
(cd "$repo" && exec env STUB_GATE="$root/gate2" scripts/mutate.sh --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/' >/dev/null 2>&1) &
crashed=$!
wait_for "$root/gate2.reached"
SCRATCH_SLOTS=1 mutate --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/'
expect "a run with every scratch tree busy exits 75 naming the holder" "$status
$out
$err" "75

every scratch tree is busy; wait for one to finish (lsof $locks/*.lock lists every holder):
  $pool/1: mutate.sh in $repo (pid $crashed)"
kill -9 $crashed
wait $crashed 2>/dev/null
rm "$root/gate2"
while lsof "$locks/1.lock" >/dev/null 2>&1; do sleep 0.05; done
SCRATCH_SLOTS=1 mutate --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/' '5s/10/11/'
expect "after a run is killed mid-mutant, the next run reclaims its slot and starts from the snapshot" "$status
$out" "1
scratch: $pool/1 at $(git -C "$repo" rev-parse --short=8 HEAD)
baseline: passed 2 tests (swift test --filter GateTests)
$killed_row
$survived_row
2 mutants: 1 killed, 1 SURVIVED"

sim_call="$pool/1/scripts/test-sim.sh --sim $udid"
head8=$(git -C "$repo" rev-parse --short=8 HEAD)

mutate --filter AuthTests App/Auth.swift '2s/return false/return true/'
expect "an App/ mutant without --sim exits 2 naming --sim" "$status
$out
$err" "2

swift test never compiles App/Auth.swift; mutate it with --sim UDID, which runs scripts/test-sim.sh in the scratch tree"

rm -f "$STUB_SIM_SEEN"
mutate --sim $udid --filter AuthTests App/Auth.swift '2s/return false/return true/' '2s/return/BREAK return/'
expect "--sim judges App/ mutants through the slot's test-sim.sh, naming the killer from its full log" "$status
$out
$(sort -u "$STUB_SIM_SEEN")" "1
scratch: $pool/1 at $head8
baseline: passed 1 test (test-sim.sh --sim $udid WorkoutTrackerTests/AuthTests)
killed       App/Auth.swift:2  sed      2s/return false/return true/  AuthTests.testDeniesByDefault
nocompile    App/Auth.swift:2  sed      2s/return/BREAK return/       App/Auth.swift:2:31: error: cannot find 'BREAK' in scope
2 mutants: 1 killed, 1 nocompile
$sim_call WorkoutTrackerTests/AuthTests"

rm -f "$STUB_SIM_SEEN"
mutate --sim $udid App/Auth.swift '2s/return false/return true/'
expect "--sim with no --filter runs unit" "$status $(sort -u "$STUB_SIM_SEEN")" "0 $sim_call unit"

mutate --sim $udid --filter AuthTests Sources/Gate/Gate.swift '5s/10/11/'
expect "under --sim, a surviving mutant in a file the simulator build never compiles is unreachable" "$status
$(tail -2 <<<"$out")" "1
unreachable  Sources/Gate/Gate.swift:5  sed      5s/10/11/  compiled out of this build (#if or no target)
1 mutant: 1 unreachable"

rm -f "$STUB_SIM_SEEN"
STUB_SIM_BUSY_AT=1 mutate --sim $udid App/Auth.swift '2s/return false/return true/'
expect "a busy simulator at the baseline exits 75" "$status
$out
$err" "75
scratch: $pool/1 at $head8
$udid is held by a test-sim.sh run (pid 1); wait for it to finish, or use another simulator"

rm -f "$STUB_SIM_SEEN"
STUB_SIM_BUSY_AT=3 mutate --sim $udid App/Auth.swift '2s/return false/return true/' '2s/false/nil/'
expect "a simulator taken mid-run prints the rows so far, then exits 75" "$status
$out
$err" "75
scratch: $pool/1 at $head8
baseline: passed 1 test (test-sim.sh --sim $udid unit)
killed       App/Auth.swift:2  sed      2s/return false/return true/  AuthTests.testDeniesByDefault
1 mutant: 1 killed; 1 not run (host busy)
$udid is held by a test-sim.sh run (pid 1); wait for it to finish, or use another simulator"

rm -f "$STUB_CALLS"
WORKOUT_DISK_FLOOR=99999999 WORKOUT_ADMIT_WAIT=0 mutate --filter GateTests Sources/Gate/Gate.swift '2s/>= 3/> 3/'
expect "free disk under WORKOUT_DISK_FLOOR on the scratch tree's volume stops the baseline with 75 before any build" "$status $(cat "$STUB_CALLS" 2>/dev/null)
$out
$(sed -E 's/free disk is [0-9]+ MB/free disk is N MB/' <<<"$err")" "75 
scratch: $pool/1 at $head8
gave up after 0 s waiting for free disk: free disk is N MB on the volume holding $pool/1, under the floor of 99999999 MB (WORKOUT_DISK_FLOOR) a build needs"

HOME=$root/home mutate --clean-scratch
expect "--clean-scratch removes every scratch tree no run holds" "$status
$(sed -E 's/\(([0-9]+) MB\)/(N MB)/' <<<"$out")
$(git -C "$repo" worktree list | grep -c "$pool/")" "0
removed $pool/1 (N MB)
removed $pool/2 (N MB)
0"

head30=$("$repo/scripts/mutate.sh" --help | head -30)
missing=""
for token in "mutate.sh --diff" "  killed " "  SURVIVED " "  flaky " "  nocompile " "  unreachable " "  error " "Exit 0 " "Exit 75 "; do
    grep -qF -- "$token" <<<"$head30" || missing="$missing [$token]"
done
expect "the first 30 lines of --help carry an example, every outcome, and the exit codes" "${missing:-none missing}" "none missing"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
