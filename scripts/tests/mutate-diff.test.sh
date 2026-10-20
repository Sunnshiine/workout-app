#!/bin/bash
# shellcheck disable=SC2016  # stub and expected text hold literal $
set -uo pipefail

# shellcheck source=scripts/tests/mutate-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/mutate-harness.sh"

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
not run      Sources/Gate/Gate.swift:8    compare  >= -> >
5 mutants: 1 killed, 2 SURVIVED, 1 nocompile, 1 unreachable; 1 not run (--max 4)"
expect "a generated mutant's line keeps its backslashes" "$(sed -n 7p "$logdir/m4.swift")" 'let pattern = "a\\d"; let strict = false'

echo 'let lateOn = true' >"$repo/Sources/Gate/Late.swift"
mutate --filter GateTests --max 3 --diff diffbase Sources
expect "--max takes each file's first mutant before any file's second, and lists the ones it left out" "$status
$(sed 1,3d <<<"$out")" "1
nocompile    Sources/Gate/Breaks.swift:1  const    breakme -> BREAK  Sources/Gate/Breaks.swift:1:5: error: cannot find 'BREAK' in scope
killed       Sources/Gate/Gate.swift:2    compare  >= -> >           GateTests.testOpensAtFour +1
SURVIVED     Sources/Gate/Late.swift:1    bool     true -> false
not run      Sources/Gate/Gate.swift:6    bool     true -> false
not run      Sources/Gate/Gate.swift:7    bool     true -> false
not run      Sources/Gate/Gate.swift:8    compare  >= -> >
3 mutants: 1 killed, 1 SURVIVED, 1 nocompile; 3 not run (--max 3)"
rm "$repo/Sources/Gate/Late.swift"

echo 'let iosOnly = true' >"$repo/Sources/Gate/Platform.swift"
mutate --diff diffbase Sources/Gate/Platform.swift
expect "--diff lists a line an #if compiles out of swift test as unreachable and claims no scratch tree" "$status
$out" "1
mutants: 1 on 1 changed line in 1 file since $diffbase
unreachable  Sources/Gate/Platform.swift:1  bool     true -> false  an #if compiles it out of swift test; rerun with --sim UDID
1 mutant: 1 unreachable"
rm "$repo/Sources/Gate/Platform.swift"

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
$(tail -3 <<<"$out")" "1
killed       Sources/Gate/Gate.swift:2  compare  >= -> >           GateTests.testOpensAtFour +1
not run      Sources/Gate/Wall.swift:1  const    breakme -> BREAK
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
