# shellcheck shell=bash
# shellcheck disable=SC2016  # stub and expected text hold literal $

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
cp "$script_dir/../mutate.sh" "$script_dir/../mutate-usage.sh" "$script_dir/../scratch-tree.sh" "$script_dir/../test-log.awk" "$repo/scripts/"

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
    *HANG*) python3 -c 'import os, time; os.setpgid(0, 0); time.sleep(600)' & echo $! >"$STUB_HANG_PID"; wait ;;
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
/iosOnly/ && platform == "macOS" { m = $0; sub(/true/, "false", m); print path "\t" FNR "\tbool\ttrue\tfalse\t" m >>compiledOut; next }
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
udid=SIM-UDID-1
