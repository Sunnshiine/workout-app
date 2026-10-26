#!/bin/bash
set -uo pipefail

usage() {
    cat <<'EOF'
scripts/ui-flake-guard.sh --xctestrun FILE --destination DEST [--base REV] [--iterations N] [--budget S] [--out DIR]

Repeats the UI tests scripts/changed-tests.sh --ui selects since REV (default origin/main) up to N
times (default 5), stopping at the first failure, with test-without-building from FILE on DEST.
CI passes HEAD^1 on a pull request and HEAD on a push, which selects nothing. Unlike
scripts/flake-guard.sh it adds no CPU load: busy loops beside a simulator on a 3-core runner make
the UI tests' few-second waits fail, which tests the runner, not the test.

The run is stopped after S seconds (--budget, default 300). A failure names each failing test and
the line that reproduces it locally.

The last line is the status line:
  ui-flake-guard: result=<nothing|passed|stopped|failed|broken> tests=<n> iterations=<n> wall=<s> exit=<e>

Exits 0 when nothing was selected, every repetition passed, or the budget stopped a run; 1 when a
test failed; 2 on a usage error or a REV git cannot resolve; 65 when xcodebuild ran none of the
selection.
EOF
}

xctestrun="" destination="" base=origin/main iterations=5 budget=300 out=.build/ui-flake-guard
while [ $# -gt 0 ]; do
    case $1 in
        -h | --help) usage; exit 0 ;;
        --xctestrun | --destination | --base | --iterations | --budget | --out) [ $# -ge 2 ] || { usage >&2; exit 2; } ;;
        *) usage >&2; exit 2 ;;
    esac
    case $1 in
        --xctestrun) xctestrun=$2 ;;
        --destination) destination=$2 ;;
        --base) base=$2 ;;
        --iterations) iterations=$2 ;;
        --budget) budget=$2 ;;
        --out) out=$2 ;;
    esac
    shift 2
done
[ -n "$xctestrun" ] && [ -n "$destination" ] || { usage >&2; exit 2; }
for number in "$iterations" "$budget"; do
    case $number in '' | *[!0-9]*) usage >&2; exit 2 ;; esac
done

repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
log=$out/ui-flake-guard.log
selected=0 wall=0
finish() {
    echo "ui-flake-guard: result=$1 tests=$selected iterations=$iterations wall=$wall exit=$2"
    exit "$2"
}

"$repo/scripts/changed-tests.sh" --ui --base "$base" >"$out/changed.tsv" || exit 2
selected=$(wc -l <"$out/changed.tsv" | tr -d ' ')
if [ "$selected" -eq 0 ]; then
    echo "ui-flake-guard: nothing to repeat; no UI test changed since $base."
    finish nothing 0
fi
echo "repeating $selected changed UI tests up to $iterations times:"
sed 's/^/  /' "$out/changed.tsv"
only=()
while IFS=$'\t' read -r _ id; do only+=("-only-testing:WorkoutTrackerUITests/$id"); done <"$out/changed.tsv"

rm -rf "$out/UIFlakeGuard.xcresult"
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" "${only[@]}" \
    -test-iterations "$iterations" -run-tests-until-failure \
    -resultBundlePath "$out/UIFlakeGuard.xcresult" -collect-test-diagnostics never >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null' EXIT
start=$SECONDS
ended=exited
while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$budget" ]; then ended=budget; break; fi
    sleep 1
done
wall=$((SECONDS - start))
status=0
if [ "$ended" = budget ]; then
    kill -TERM "$pid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -KILL "$pid" 2>/dev/null
fi
wait "$pid" 2>/dev/null || status=$?
trap - EXIT

failing=$(awk '/^Failing tests:/ { block = 1; next } block && /^\t/ { sub(/^\t+/, ""); print; next } { block = 0 }' "$log")
if [ -n "$failing" ] || { [ "$ended" = exited ] && [ "$status" -ne 0 ]; }; then
    echo "ui-flake-guard: FAILED within $iterations repetitions of the changed UI tests"
    "$repo/scripts/test-log-summary.sh" --cause "$log"
    while IFS=$'\t' read -r declaration id; do
        echo "reproduce: scripts/test-sim.sh WorkoutTrackerUITests/$id  # $declaration"
        [ "${GITHUB_ACTIONS:-}" != true ] ||
            echo "::error file=${declaration%:*},line=${declaration##*:},title=UI test failed on repeat::$id failed within $iterations repetitions"
    done < <(awk -F'\t' 'NR == FNR { f[$0] = 1; next } { split($2, p, "/"); if ((p[1] "." p[2] "()") in f || (p[1] "." p[2]) in f) print }' <(printf '%s\n' "$failing") "$out/changed.tsv")
    finish failed 1
fi
ran=$(grep -cE "Test [Cc]ase .*(passed|failed)" "$log")
[ "$ran" -gt 0 ] || { echo "ui-flake-guard: xcodebuild ran none of the selection; see $log" >&2; finish broken 65; }
if [ "$ended" = budget ]; then
    echo "ui-flake-guard: stopped at the ${budget}s budget after $ran test runs; every one passed"
    finish stopped 0
fi
echo "ui-flake-guard: passed; $selected tests, $ran runs, in ${wall}s"
finish passed 0
