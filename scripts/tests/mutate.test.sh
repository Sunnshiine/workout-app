#!/bin/bash
# shellcheck disable=SC2016  # stub and expected text hold literal $
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
trap 'rm -f "$root"/gate*; sleep 0.3; rm -rf "$root"' EXIT
export LC_ALL=C GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export PATH="$root/bin:$PATH" STUB_CALLS=$root/calls STUB_HANG_PID=$root/hang.pid STUB_WATCH=$root/watch STUB_CALLER=$root/repo STUB_SIM_SEEN=$root/sim-seen
repo=$root/repo
pool=$repo/.build/scratch locks=$repo/.git/scratch-locks
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}
wait_for() { local _; for _ in $(seq 1 200); do [ -e "$1" ] && return; sleep 0.05; done; }

mkdir -p "$root/bin" "$repo/scripts" "$repo/Sources/Gate" "$repo/App"
cp "$script_dir/../mutate.sh" "$script_dir/../scratch-tree.sh" "$script_dir/../test-log.awk" "$repo/scripts/"

cat >"$root/bin/swift" <<'STUB'
#!/bin/bash
gate=Sources/Gate/Gate.swift
if [ "$1" = build ]; then
    if [ -n "${STUB_DISK_FULL:-}" ] && [ "$(sed -n 2p $gate)" != "    count >= 3" ]; then
        echo "error: no space left on device" >&2
        exit 1
    fi
    probe=$(awk '/^#if canImport\(UIKit\)/ { off = 1 } /^#endif/ { off = 0 }
        /#error\("mutate.sh reach probe"\)/ && !off { print FILENAME ":" FNR; exit }' $(find Sources -name '*.swift'))
    [ -z "$probe" ] || { echo "$PWD/$probe:1: error: mutate.sh reach probe" >&2; exit 1; }
    broken=$(grep -rn BREAK Sources | head -1 | cut -d: -f1,2)
    [ -z "$broken" ] || { echo "error: SwiftCompile normal arm64 $PWD/${broken%:*} failed with a nonzero exit code." >&2
        echo "$PWD/$broken:5: error: cannot find 'BREAK' in scope" >&2; exit 1; }
    exit 0
fi
echo $(($(cat "$STUB_CALLS" 2>/dev/null || echo 0) + 1)) >"$STUB_CALLS"
{ git -C "$STUB_CALLER" status --porcelain; shasum "$STUB_CALLER"/Sources/Gate/*; echo "slot line 5: $(sed -n 5p $gate)"; } >>"$STUB_WATCH"
if [ -n "${STUB_GATE:-}" ] && [ "$(sed -n 2p $gate)" != "    count >= 3" ]; then
    touch "$STUB_GATE.reached"
    while [ -e "$STUB_GATE" ]; do sleep 0.05; done
fi
shift
filters=()
while [ $# -gt 0 ]; do [ "$1" = --filter ] && filters+=("$2") && shift; shift; done
selected() { [ ${#filters[@]} = 0 ] && return 0; for f in "${filters[@]}"; do case $1 in *"$f"*) return 0 ;; esac; done; return 1; }
line2_ok() { [ "$(sed -n 2p $gate)" = "    count >= 3" ]; }
crash() { echo "error: Process '/Applications/Xcode.app/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path $PWD/.build/T.xctest' exited with unexpected signal code 5" >&2; exit 1; }
case $(sed -n 5p $gate) in
    *HANG*) sleep 600 & echo $! >"$STUB_HANG_PID"; wait ;;
    *EXPLODE*) echo "error: Process '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path $PWD/.build/out/Products/Debug/WorkoutTrackerTests.xctest/Contents/MacOS/WorkoutTrackerTests --testing-library swift-testing' exited with code 3" >&2; exit 1 ;;
    *CRASH_IN_TEST*) printf '%s\n' "◇ Test run started." "◇ Test limitHolds() started."; crash ;;
    *CRASH*) echo "◇ Test run started."; crash ;;
esac
failed=0 swift_tests=0 xctests=0
if selected GateTests.testOpensAtFour; then
    xctests=1
    if line2_ok; then echo "Test Case '-[GateModuleTests.GateTests testOpensAtFour]' passed (0.001 seconds)."
    else echo "Test Case '-[GateModuleTests.GateTests testOpensAtFour]' failed (0.001 seconds)."; failed=1; fi
fi
echo "	 Executed $xctests tests, with $failed failures (0 unexpected) in 0.001 (0.001) seconds"
echo "◇ Test run started."
for t in GateTests.gateOpensAtThree NameTests.nameIsGate; do
    selected $t || continue
    swift_tests=$((swift_tests + 1))
    case $t in
        GateTests.*) line2_ok ;;
        NameTests.*) grep -q '^let gateName = "gate"$' $gate && [ "$(cat "$STUB_CALLS")" -lt "${STUB_FLAKY_FROM:-999}" ] ;;
    esac && echo "✔ Test ${t#*.}() passed after 0.001 seconds." || { echo "✘ Test ${t#*.}() failed after 0.001 seconds with 1 issue."; failed=1; }
done
echo "✔ Test run with $swift_tests tests in 2 suites passed after 0.002 seconds."
exit $failed
STUB
chmod +x "$root/bin/swift"

git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
printf '.build/\nSecrets.xcconfig\n' >"$repo/.gitignore"
printf '%s\n' 'func gateOpens(_ count: Int) -> Bool {' '    count >= 3' '}' 'let gateName = "gate"' 'let gateLimit = 10' >"$repo/Sources/Gate/Gate.swift"
printf '%s\n' 'enum Auth {' '    static func ok() -> Bool { return false }' '}' >"$repo/App/Auth.swift"
cat >"$repo/scripts/mutants.awk" <<'STUB'
BEGIN { while ((getline n < changed) > 0) want[n] = 1 }
!want[FNR] { next }
/ >= / { m = $0; sub(/ >= /, " > ", m); print path "\t" FNR "\tcompare\t>=\t>\t" m }
/true/ { m = $0; sub(/true/, "false", m); print path "\t" FNR "\tbool\ttrue\tfalse\t" m }
/breakme/ { m = $0; sub(/breakme/, "BREAK", m); print path "\t" FNR "\tconst\tbreakme\tBREAK\t" m }
STUB

cat >"$repo/scripts/test-sim.sh" <<'STUB'
#!/bin/bash
echo "$0 $*" >>"$STUB_SIM_SEEN"
dir=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(wc -l <"$STUB_SIM_SEEN")" -eq "${STUB_SIM_BUSY_AT:-0}" ]; then
    echo "$2 is held by a test-sim.sh run (pid 1); wait for it to finish, or use another simulator" >&2
    exit 75
fi
if grep -qE 'BREAK|#error' "$dir/App/Auth.swift"; then
    echo "$dir/App/Auth.swift:2:31: error: cannot find 'BREAK' in scope" >&2
    echo "build log: $dir/.build/test-sim/build.log" >&2
    exit 65
fi
mkdir -p "$dir/.build/test-sim"
log=$dir/.build/test-sim/test.log
echo "log: $log"
if grep -q 'return false' "$dir/App/Auth.swift"; then
    printf "Test Case '-[WorkoutTrackerTests.AuthTests testDeniesByDefault]' passed (0.001 seconds).\n\t Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds\n" >"$log"
    echo "	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds"
    exit 0
fi
printf "Test Case '-[WorkoutTrackerTests.AuthTests testDeniesByDefault]' failed (0.001 seconds).\n\t Executed 1 test, with 1 failure (0 unexpected) in 0.001 (0.001) seconds\n" >"$log"
printf 'Failing tests:\n\tAuthTests.testDeniesByDefault()\n'
exit 65
STUB
chmod +x "$repo/scripts/test-sim.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm base

mutate() {
    (cd "$repo" && scripts/mutate.sh "$@") >"$root/out" 2>"$root/err"
    status=$?
    logdir=$(sed -n '1s/^log: //p' "$root/out")
    out=$(sed '1{/^log: /d;}' "$root/out")
    err=$(cat "$root/err")
}
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
expect "a SIGKILL to mutate.sh's process group kills the test it started and frees the slot within a second" "$(
    if kill -0 "$(cat "$root/hang.pid")" 2>/dev/null; then echo "the hung test still runs"; else echo "the hung test is gone"; fi
    lsof -t "$locks/1.lock" 2>/dev/null | wc -l | tr -d ' ')" "the hung test is gone
0"

MUTATE_TIMEOUT=2 mutate --filter GateTests Sources/Gate/Gate.swift '5s/10/HANG/'
expect "a mutant that runs past MUTATE_TIMEOUT is killed with its whole process group" "$status
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

udid=SIM-UDID-1
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
1 mutant: 1 killed; 1 not run (simulator busy)
$udid is held by a test-sim.sh run (pid 1); wait for it to finish, or use another simulator"

git -C "$repo" checkout -q -b diffbase
sed -i '' 's/count >= 3/count > 2/' "$repo/Sources/Gate/Gate.swift"
git -C "$repo" commit -qam "diff base"
git -C "$repo" checkout -q -b feature
sed -i '' 's/count > 2/count >= 3/' "$repo/Sources/Gate/Gate.swift"
printf '%s\n' 'let gateOn = true' 'let pattern = "a\\d"; let strict = true' >>"$repo/Sources/Gate/Gate.swift"
sed -i '' '3i\
    static let on = true
' "$repo/App/Auth.swift"
echo 'let breakme = 1' >"$repo/Sources/Gate/Breaks.swift"
git -C "$repo" add -A && git -C "$repo" commit -qm feature
echo 'let wide = 1 >= 0' >>"$repo/Sources/Gate/Gate.swift"
diffbase=$(git -C "$repo" rev-parse --short=8 diffbase)
head8=$(git -C "$repo" rev-parse --short=8 HEAD)

mutate --filter GateTests --max 4 --diff diffbase
expect "--diff mutates the changed lines, uncommitted ones included; --max caps the runnable ones and lists the unreachable after" "$status
$out" "1
mutants: 6 on 6 changed lines in 3 files since $diffbase
scratch: $pool/1 at $head8 + your uncommitted changes
baseline: passed 2 tests (swift test --filter GateTests)
nocompile    Sources/Gate/Breaks.swift:1  const    breakme -> BREAK  Sources/Gate/Breaks.swift:1:5: error: cannot find 'BREAK' in scope
killed       Sources/Gate/Gate.swift:2    compare  >= -> >           GateTests.testOpensAtFour +1
SURVIVED     Sources/Gate/Gate.swift:6    bool     true -> false
SURVIVED     Sources/Gate/Gate.swift:7    bool     true -> false
unreachable  App/Auth.swift:3             bool     true -> false     swift test never compiles it; rerun with --sim UDID
5 mutants: 1 killed, 2 SURVIVED, 1 nocompile, 1 unreachable; 1 not run (--max 4)"
expect "a generated mutant's line keeps its backslashes" "$(sed -n 7p "$logdir/m4.swift")" 'let pattern = "a\\d"; let strict = false'

mutate --diff diffbase Sources/Gate/Breaks.swift
expect "a run whose only mutant does not build killed nothing, so it fails" "$status
$(tail -2 <<<"$out")" "1
nocompile    Sources/Gate/Breaks.swift:1  const    breakme -> BREAK  Sources/Gate/Breaks.swift:1:5: error: cannot find 'BREAK' in scope
1 mutant: 1 nocompile"

rm -f "$STUB_SIM_SEEN"
mutate --diff diffbase App
expect "--diff on App/ without --sim lists each mutant as unreachable and claims no scratch tree" "$status
$out" "1
mutants: 1 on 1 changed line in 1 file since $diffbase
unreachable  App/Auth.swift:3  bool     true -> false  swift test never compiles it; rerun with --sim UDID
1 mutant: 1 unreachable"

mutate --sim $udid --diff diffbase App
expect "--diff on App/ with --sim runs it through test-sim.sh" "$status
$(tail -2 <<<"$out")" "1
SURVIVED     App/Auth.swift:3  bool     true -> false
1 mutant: 1 SURVIVED"

git -C "$repo" checkout -q -- .
mutate --diff HEAD
expect "--diff with no changed lines exits 0 before claiming a scratch tree" "$status
$out" "0
mutants: 0 on 0 changed lines in 0 files since $head8"

git -C "$repo" checkout -q -b pair diffbase
sed -i '' 's/count > 2/count >= 3/' "$repo/Sources/Gate/Gate.swift"
echo 'let breakme = 1' >"$repo/Sources/Gate/Wall.swift"
git -C "$repo" add -A && git -C "$repo" commit -qm pair

mutate --filter GateTests --diff diffbase
expect "a generated mutant that does not build does not fail a run that killed one" "$status
$(tail -3 <<<"$out")" "0
killed       Sources/Gate/Gate.swift:2  compare  >= -> >           GateTests.testOpensAtFour +1
nocompile    Sources/Gate/Wall.swift:1  const    breakme -> BREAK  Sources/Gate/Wall.swift:1:5: error: cannot find 'BREAK' in scope
2 mutants: 1 killed, 1 nocompile"

STUB_DISK_FULL=1 mutate --filter GateTests --diff diffbase Sources/Gate/Gate.swift
expect "a build that fails outside the mutated file is an error, never nocompile" "$status
$(tail -2 <<<"$out")" "1
error        Sources/Gate/Gate.swift:2  compare  >= -> >  error: no space left on device
1 mutant: 1 error"

mutate --filter GateTests --max 1 --diff diffbase
expect "a run that --max left mutants unrun fails even when it killed every one it ran" "$status
$(tail -2 <<<"$out")" "1
killed       Sources/Gate/Gate.swift:2  compare  >= -> >  GateTests.testOpensAtFour +1
1 mutant: 1 killed; 1 not run (--max 1)"

(cd "$repo/Sources/Gate" && ../../scripts/mutate.sh --filter GateTests --diff diffbase Gate.swift) >"$root/out" 2>"$root/err"
expect "a --diff PATH is resolved from the current directory" "$? $(tail -2 "$root/out")" "0 killed       Sources/Gate/Gate.swift:2  compare  >= -> >  GateTests.testOpensAtFour +1
1 mutant: 1 killed"

mutate --diff diffbase Source/Gate
expect "a --diff PATH that does not exist exits 2" "$status
$out
$err" "2

Source/Gate: no such file or directory"

mutate --diff diffbase .build/mutate
expect "a --diff PATH that holds no file of the working tree exits 2" "$status
$out
$err" "2

.build/mutate matches no file in your working tree (an ignored file cannot be mutated)"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
