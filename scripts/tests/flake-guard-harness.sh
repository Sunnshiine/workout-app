# shellcheck shell=bash
# shellcheck disable=SC2034  # flake-guard.test.sh reads the logs and the run directory set here
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
build=$root/build
mkdir -p "$repo/scripts" "$repo/Tests/Unit" "$root/bin" "$build/DerivedData/Build/Products/Debug/WorkoutTrackerTests.xctest"
find "$script_dir/.." -maxdepth 1 -type f -exec cp {} "$repo/scripts/" \;
unset GITHUB_ACTIONS
export STUB_ARGS=$root/args STUB_INVENTORY=$root/inventory.json
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/sh
case " $* " in
    *" -enumerate-tests "*)
        printf '%s\n' "$@" >"$STUB_ARGS.enumerate"
        while [ "$1" != -test-enumeration-output-path ]; do shift; done
        cat "$STUB_INVENTORY" >"$2"
        exit 0 ;;
esac
printf '%s\n' "$@" >"$STUB_ARGS.run"
printf '%s\n' "$STUB_LOG"
[ -z "${STUB_SLEEP:-}" ] || sleep "$STUB_SLEEP"
exit "${STUB_RC:-0}"
STUB
cat >"$root/bin/sysctl" <<'STUB'
#!/bin/sh
case $2 in
    hw.ncpu) echo 2 ;;
    vm.loadavg) echo '{ 1.50 1.25 1.00 }' ;;
esac
STUB
chmod +x "$root/bin/xcodebuild" "$root/bin/sysctl"

cat >"$repo/Tests/Unit/NestedTests.swift" <<'SWIFT'
import Testing

struct NestedTests {
    @Test func aNestedTest() { #expect(true) }
    @Test func aGuardedTest() { #expect(true) }
}

@Test(arguments: [1, 2])
func aParametrizedTest(n: Int) { #expect(n > 0) }
SWIFT
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
git -C "$repo" add -A && git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)

inventory() {
    local ids="" id
    for id in "$@"; do ids="$ids${ids:+, }{\"identifier\": \"$id\"}"; done
    printf '{"errors": [], "values": [{"disabledTests": [], "enabledTests": [%s], "testPlan": "WorkoutTracker"}]}\n' "$ids" >"$STUB_INVENTORY"
}
inventory 'WorkoutTrackerTests/NestedTests/aNestedTest()' 'WorkoutTrackerTests/aParametrizedTest(n:)' \
    'WorkoutTrackerTests/OtherTests/anUntouchedTest()'

# Runs the guard from the fixture repo with the stubs first on PATH, sending it TERM after
# $SIGTERM_AFTER seconds when that is set. Later flags override the defaults it passes.
guard() {
    rm -f "$STUB_ARGS".*
    (cd "$repo" && PATH="$root/bin:$PATH" exec scripts/flake-guard.sh --xcodebuild "$build" --base "$base" --load 0 "$@" \
        >"$root/out" 2>"$root/err") &
    [ -z "${SIGTERM_AFTER:-}" ] || { sleep "$SIGTERM_AFTER"; kill -TERM $!; }
    wait $!
    status=$?
    run=$(sed -n 's/^log: //p' "$root/out")
    out=$(grep -v '^log: ' "$root/out" | sed -E 's/ in [0-9]+s$/ in Ns/')
    err=$(cat "$root/err")
    last=$(tail -1 "$root/out")
}

status_line() {
    echo "flake-guard: result=$1 tests=$2 repetitions=$3/20 hogs=0 ncpu=2 load1=1.50/1.50 exit=$4"
}

# verify NAME EXIT LAST [LINE...]: the exit code, the last stdout line, and each LINE on stdout,
# or on stderr when it starts with 2>.
verify() {
    local name=$1 want_status=$2 want_last=$3 line problems=""
    shift 3
    [ "$status" = "$want_status" ] || problems="$problems exit $status, want $want_status;"
    [ "$last" = "$want_last" ] || problems="$problems last line is: $last;"
    for line in "$@"; do
        case $line in
            '2>'*) printf '%s\n' "$err" | grep -Fxq -- "${line#2>}" ;;
            *) printf '%s\n' "$out" | grep -Fxq -- "$line" ;;
        esac || problems="$problems missing: $line;"
    done
    if [ -z "$problems" ]; then
        ok "$name"
    else
        bad "$name:$problems"
        printf '    stdout:\n%s\n    stderr:\n%s\n' "$out" "$err"
    fi
}

same() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}

# follows FLAG VALUE: the run launch passed VALUE right after FLAG.
follows() {
    awk -v flag="$1" -v value="$2" 'previous == flag && $0 == value { found = 1 } { previous = $0 } END { exit !found }' \
        "$STUB_ARGS.run" 2>/dev/null
}

passing='Running tests multiple times until a failure occurs. Running tests repeatedly up to 20 times.
◇ Test run started.
◇ Test aNestedTest() started.
◇ Test aParametrizedTest(n:) started.
◇ Test aNestedTest() started (repetition 2).
◇ Test case passing 1 argument n → 1 to aParametrizedTest(n:) started (repetition 2).
◇ Test case passing 1 argument n → 2 to aParametrizedTest(n:) started (repetition 2).
◇ Test aNestedTest() started (repetition 20).
◇ Test case passing 1 argument n → 1 to aParametrizedTest(n:) started (repetition 20).
◇ Test case passing 1 argument n → 2 to aParametrizedTest(n:) started (repetition 20).
✔ Test aNestedTest() passed after 0.010 seconds.
✔ Test aParametrizedTest(n:) with 2 test cases passed after 0.011 seconds.
✔ Test run with 2 tests in 1 suite passed after 0.012 seconds.
** TEST EXECUTE SUCCEEDED **'

failing_on_seven='Running tests multiple times until a failure occurs. Running tests repeatedly up to 20 times.
◇ Test run started.
◇ Test aNestedTest() started.
◇ Test aParametrizedTest(n:) started.
◇ Test case passing 1 argument n → 1 to aParametrizedTest(n:) started (repetition 2).
◇ Test case passing 1 argument n → 2 to aParametrizedTest(n:) started (repetition 2).
◇ Test aNestedTest() started (repetition 7).
✘ Test aNestedTest() recorded an issue at NestedTests.swift:4:31: Expectation failed: elapsed < .seconds(10)
✘ Test aNestedTest() failed after 0.900 seconds with 1 issue.
✘ Test run with 2 tests in 1 suite failed after 0.901 seconds with 1 issue.

Test session results, code coverage, and logs:
	/tmp/run.xcresult

Failing tests:
	NestedTests.aNestedTest()

** TEST EXECUTE FAILED **'

crashed_on_two='◇ Test run started.
◇ Test aNestedTest() started.
◇ Test aParametrizedTest(n:) started.
◇ Test aNestedTest() started (repetition 2).
✔ Test aParametrizedTest(n:) with 2 test cases passed after 0.011 seconds.

Test session results, code coverage, and logs:
	/tmp/run.xcresult

** TEST EXECUTE FAILED **'

one_of_two_ran='◇ Test run started.
◇ Test aNestedTest() started.
◇ Test aNestedTest() started (repetition 2).
✔ Test aNestedTest() passed after 0.010 seconds.
✔ Test run with 1 test in 1 suite passed after 0.012 seconds.
** TEST EXECUTE SUCCEEDED **'

never_repeated='◇ Test run started.
◇ Test aNestedTest() started.
◇ Test aParametrizedTest(n:) started.
✔ Test aNestedTest() passed after 0.010 seconds.
✔ Test aParametrizedTest(n:) with 2 test cases passed after 0.011 seconds.
✔ Test run with 2 tests in 1 suite passed after 0.012 seconds.
** TEST EXECUTE SUCCEEDED **'

started_once='◇ Test run started.
◇ Test aNestedTest() started.'

repeating='◇ Test run started.
◇ Test aNestedTest() started.
◇ Test aParametrizedTest(n:) started.
◇ Test aNestedTest() started (repetition 2).
◇ Test case passing 1 argument n → 1 to aParametrizedTest(n:) started (repetition 2).
◇ Test case passing 1 argument n → 2 to aParametrizedTest(n:) started (repetition 2).
◇ Test aNestedTest() started (repetition 3).'
