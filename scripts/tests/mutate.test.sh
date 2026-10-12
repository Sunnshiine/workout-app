#!/bin/bash
# shellcheck disable=SC2016  # stub and expected text hold literal $
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
trap 'rm -f "$root"/gate*; sleep 0.3; rm -rf "$root"' EXIT
export LC_ALL=C GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export PATH="$root/bin:$PATH" STUB_WATCH=$root/watch STUB_CALLER=$root/repo STUB_SIM_SEEN=$root/sim-seen
repo=$root/repo
pool=$repo/.build/scratch
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}
wait_for() { local _; for _ in $(seq 1 200); do [ -e "$1" ] && return; sleep 0.05; done; }

mkdir -p "$root/bin" "$repo/scripts" "$repo/Sources/Gate" "$repo/App"
cp "$script_dir/../mutate.sh" "$script_dir/../scratch-tree.sh" "$script_dir/../test-failures.awk" "$repo/scripts/"

# A fake suite over the tree it runs in. gateOpensAtThree (Swift Testing) and GateTests.testOpensAtFour
# (XCTest) pin line 2 of Gate.swift, nameIsGate pins line 4, and nothing pins line 5. swift build fails
# on BREAK. While $STUB_GATE exists and a mutant sits on line 2, it waits, so a test can act mid-run.
cat >"$root/bin/swift" <<'STUB'
#!/bin/bash
gate=Sources/Gate/Gate.swift
if [ "$1" = build ]; then
    broken=$(grep -rn BREAK Sources | head -1 | cut -d: -f1,2)
    [ -z "$broken" ] || { echo "$PWD/$broken:5: error: cannot find 'BREAK' in scope" >&2; exit 1; }
    exit 0
fi
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
        NameTests.*) grep -q '^let gateName = "gate"$' $gate ;;
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
# A stand-in for scripts/mutants.awk with its interface: on each changed line, >= becomes >, true
# becomes false, and breakme becomes BREAK.
cat >"$repo/scripts/mutants.awk" <<'STUB'
BEGIN { while ((getline n < changed) > 0) want[n] = 1 }
!want[FNR] { next }
/ >= / { m = $0; sub(/ >= /, " > ", m); print path "\t" FNR "\tcompare\t>=\t>\t" m }
/true/ { m = $0; sub(/true/, "false", m); print path "\t" FNR "\tbool\ttrue\tfalse\t" m }
/breakme/ { m = $0; sub(/breakme/, "BREAK", m); print path "\t" FNR "\tconst\tbreakme\tBREAK\t" m }
STUB

# A committed stand-in for scripts/test-sim.sh: records how it was called, then acts as a simulator
# suite over App/Auth.swift. testDeniesByDefault pins line 2. STUB_SIM_BUSY_AT=N exits 75 on call N.
cat >"$repo/scripts/test-sim.sh" <<'STUB'
#!/bin/bash
echo "$0 $*" >>"$STUB_SIM_SEEN"
dir=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(wc -l <"$STUB_SIM_SEEN")" -eq "${STUB_SIM_BUSY_AT:-0}" ]; then
    echo "$2 is held by a test-sim.sh run (pid 1); wait for it to finish, or use another simulator" >&2
    exit 75
fi
if grep -q BREAK "$dir/App/Auth.swift"; then
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

# Runs mutate.sh from the caller; sets status, out (stdout without its log: line), err, and logdir.
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

every scratch tree is busy; wait for one to finish (lsof $pool/*.lock lists every holder):
  $pool/1: mutate.sh in $repo (pid $crashed)"
kill -9 $crashed
wait $crashed 2>/dev/null
rm "$root/gate2"
while lsof "$pool/1.lock" >/dev/null 2>&1; do sleep 0.05; done
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

mutate --filter GateTests --max 5 --diff diffbase
expect "--diff mutates the changed lines, uncommitted ones included, and --max drops the rest" "$status
$out" "1
mutants: 6 on 6 changed lines in 3 files since $diffbase
scratch: $pool/1 at $head8 + your uncommitted changes
baseline: passed 2 tests (swift test --filter GateTests)
unreachable  App/Auth.swift:3             bool     true -> false     swift test never compiles it; rerun with --sim UDID
nocompile    Sources/Gate/Breaks.swift:1  const    breakme -> BREAK  Sources/Gate/Breaks.swift:1:5: error: cannot find 'BREAK' in scope
killed       Sources/Gate/Gate.swift:2    compare  >= -> >           GateTests.testOpensAtFour +1
SURVIVED     Sources/Gate/Gate.swift:6    bool     true -> false
SURVIVED     Sources/Gate/Gate.swift:7    bool     true -> false
5 mutants: 1 killed, 2 SURVIVED, 1 nocompile, 1 unreachable; 1 not run (--max 5)"
expect "a generated mutant's line keeps its backslashes" "$(sed -n 7p "$logdir/m5.swift")" 'let pattern = "a\\d"; let strict = false'

mutate --diff diffbase Sources/Gate/Breaks.swift
expect "a generated mutant that does not build does not fail the run" "$status
$(tail -2 <<<"$out")" "0
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

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
