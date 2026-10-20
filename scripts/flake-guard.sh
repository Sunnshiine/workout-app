#!/bin/bash
set -uo pipefail

usage() {
    cat <<'EOF'
scripts/flake-guard.sh --xcodebuild DIR [--base REV] [--iterations N] [--budget S] [--stall S] [--load N]

Repeats the tests scripts/changed-tests.sh selects since REV, under CPU load, on the test
products scripts/crap.sh gate --xcodebuild DIR built, with no second compile. REV defaults to
origin/main. CI passes HEAD^1 on a pull request and HEAD on a push, which selects nothing. A
checkout that changed no test runs nothing.

One xcodebuild launch repeats every selected test up to N times (default 20) and stops at the
first failure, while --load busy loops (default three per core) hold the CPU. The launch is
stopped after S seconds (--budget, default 300), and killed as hung when no test starts or
repeats for S seconds (--stall, default 120).

Prints the selection, then the verdict. A failure names each failing test, its declaration, its
first issues, and the flake-hunt.sh line that reproduces it, and under GitHub Actions annotates
the declaration. The last line is the status line. Files go under .build/flake-guard/.

Exits 0 when nothing was selected, every repetition passed, or the budget stopped a run that
repeated every test at least twice; 1 when a test failed or hung; 2 on a usage error or a REV
git cannot resolve; 65 when it cannot run what it selected: no products under DIR, an empty
enumeration, fewer tests run than selected, or no second repetition.
EOF
}

ncpu=$(sysctl -n hw.ncpu)
dir="" base=origin/main iterations=20 budget=300 stall=120 load=$((ncpu * 3))
while [ $# -gt 0 ]; do
    case $1 in
        -h | --help) usage; exit 0 ;;
        --xcodebuild | --base | --iterations | --budget | --stall | --load) [ $# -ge 2 ] || { usage >&2; exit 2; } ;;
        *) usage >&2; exit 2 ;;
    esac
    case $1 in
        --xcodebuild) dir=$2 ;;
        --base) base=$2 ;;
        --iterations) iterations=$2 ;;
        --budget) budget=$2 ;;
        --stall) stall=$2 ;;
        --load) load=$2 ;;
    esac
    shift 2
done
[ -n "$dir" ] || { usage >&2; exit 2; }
for number in "$iterations" "$budget" "$stall" "$load"; do
    case $number in '' | *[!0-9]*) usage >&2; exit 2 ;; esac
done

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo" || exit 2
run=$repo/.build/flake-guard/$(date +%Y%m%d-%H%M%S)-$$
log=$run/run.log
mkdir -p "$run"
load1() { sysctl -n vm.loadavg | awk '{ print $2 }'; }
load_before=$(load1)
echo "log: $run"
echo "host: hw.ncpu=$ncpu load1=$load_before hogs=$load"

selected=0
reached=0
finish() {
    echo "flake-guard: result=$1 tests=$selected repetitions=$reached/$iterations hogs=$load ncpu=$ncpu load1=$load_before/$(load1) exit=$2"
    exit "$2"
}
annotate() { [ "${GITHUB_ACTIONS:-}" != true ] || echo "$1"; }

# The join key between the changed declarations, the enumeration, and the log's names:
# WorkoutTrackerTests/Suite/name(label:), Suite.name(), and "name (crashed)" all reduce to name.
base_name='function base(s) { sub(/[( ].*/, "", s); sub(/.*[\/.]/, "", s); return s }'

# The gate's workspace and DerivedData, so the products it built run as they are.
xcb() {
    xcodebuild test-without-building -workspace .swiftpm/xcode/package.xcworkspace -scheme WorkoutTracker \
        -destination platform=macOS -skipPackagePluginValidation -skipMacroValidation \
        -derivedDataPath "$dir/DerivedData" -clonedSourcePackagesDirPath "$dir/SourcePackages" "$@"
}

scripts/changed-tests.sh --base "$base" >"$run/changed.tsv" || exit 2
if [ ! -s "$run/changed.tsv" ]; then
    echo "flake-guard: nothing to repeat; no test file changed since $base."
    finish nothing 0
fi

if [ ! -d "$dir/DerivedData/Build/Products/Debug/WorkoutTrackerTests.xctest" ]; then
    echo "flake-guard: no test products under $dir; run scripts/crap.sh gate --xcodebuild $dir first." >&2
    finish broken 65
fi

xcb -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
    -test-enumeration-output-path "$run/inventory.json" >"$run/enumerate.log" 2>&1 &&
    python3 -I -c 'import json, sys
for value in json.load(open(sys.argv[1]))["values"]:
    for test in value["enabledTests"]:
        print(test["identifier"])' "$run/inventory.json" >"$run/inventory.ids" 2>>"$run/enumerate.log"
if [ ! -s "$run/inventory.ids" ]; then
    echo "flake-guard: listing the tests the products hold found none; see $run/enumerate.log" >&2
    finish broken 65
fi

awk -F'\t' -v missing="$run/missing" "$base_name"'
    FILENAME == ARGV[1] { declaration[$2] = $1; next }
    base($0) in declaration { print $0 "\t" declaration[base($0)]; found[base($0)] = 1 }
    END { for (name in declaration) if (!(name in found)) print name >missing }
' "$run/changed.tsv" "$run/inventory.ids" | LC_ALL=C sort >"$run/selection.tsv"
cut -f1 "$run/selection.tsv" >"$run/selection.ids"
selected=$(wc -l <"$run/selection.ids" | tr -d ' ')
if [ "$selected" -gt 0 ]; then
    echo "selected $selected tests from $(wc -l <"$run/changed.tsv" | tr -d ' ') changed declarations:"
    awk -F'\t' '{ print "  " $1 "  " $2 }' "$run/selection.tsv"
fi
[ ! -s "$run/missing" ] ||
    echo "not in the enumeration (platform-guarded or excluded): $(LC_ALL=C sort "$run/missing" | paste -sd' ' -)"
if [ "$selected" -eq 0 ]; then
    echo "flake-guard: nothing to repeat; no changed test is in the enumeration."
    finish nothing 0
fi

# reached: identifier, declaration, and the highest repetition the log shows that test starting,
# one row per selected test. A display name hides the identifier from the log, so a test the log
# never names gets the run's highest. unfinished: each test, as logged, that started and never
# passed or failed, with its declaration when its base name maps to one.
tally() {
    awk -F'\t' -v want="$1" "$base_name"'
        FILENAME == ARGV[1] { id[++n] = $1; declaration[n] = $2; at[base($1)] = $2; next }
        / Test run started/ { next }
        /^[^ ]+ Test .* started( \(repetition [0-9]+\))?\.$/ {
            name = $0
            k = match(name, / started \(repetition [0-9]+\)\.$/) ? substr(name, RSTART + 21) + 0 : 1
            sub(/ started( \(repetition [0-9]+\))?\.$/, "", name)
            # A parameterized test logs its own start once; each repetition logs only its cases, as
            # "Test case passing 1 argument n → 1 to name(n:) started (repetition 2).".
            if (name ~ /^[^ ]+ Test case passing /) {
                for (i = 1; i <= n; i++) {
                    last = id[i]
                    sub(/.*\//, "", last)
                    if (substr(name, length(name) - length(last) - 3) == " to " last && k > reached[last]) reached[last] = k
                }
                if (k > most) most = k
                next
            }
            sub(/^[^ ]+ Test /, "", name)
            if (k > reached[name]) reached[name] = k
            if (k > most) most = k
            running[name] = 1
            next
        }
        /^[^ ]+ Test .* (passed|failed) after / && !/ Test run with / {
            name = $0
            sub(/^[^ ]+ Test /, "", name)
            sub(/ (with [0-9]+ test cases? )?(passed|failed) after .*/, "", name)
            delete running[name]
        }
        END {
            if (want == "reached") for (i = 1; i <= n; i++) {
                last = id[i]
                sub(/.*\//, "", last)
                print id[i] "\t" declaration[i] "\t" (last in reached ? reached[last] : most + 0)
            }
            else for (name in running) print name "\t" at[base(name)]
        }' "$run/selection.tsv" "$log"
}
tally_reached() {
    tally reached >"$run/reached.tsv"
    reached=$(cut -f3 "$run/reached.tsv" | sort -n | head -1)
}

stop() {
    kill -TERM "$pid" 2>/dev/null
    for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

report_hung() {
    echo "flake-guard: $1; killed the run on repetition $reached of $iterations"
    tally unfinished | LC_ALL=C sort >"$run/unfinished.tsv"
    [ -s "$run/unfinished.tsv" ] || echo "  no test was running when it stopped; see $log"
    while IFS=$'\t' read -r name declaration; do
        echo "  ✘ $name${declaration:+  $declaration}"
        annotate "::error ${declaration:+file=${declaration%:*},line=${declaration##*:},}title=hung under load::$name was still running when the guard killed the run ($1) under $load busy loops on $ncpu cores"
    done <"$run/unfinished.tsv"
    finish hung 1
}

hogs=()
pid=""
trap 'kill ${hogs[@]+"${hogs[@]}"} $pid 2>/dev/null || true' EXIT
for ((i = 0; i < load; i++)); do
    yes >/dev/null &
    hogs+=($!)
done
echo "run: $iterations iterations of $selected tests under $load hogs, budget ${budget}s, stall ${stall}s"

xcb -collect-test-diagnostics never -resultBundlePath "$run/run.xcresult" \
    -only-testing "@$run/selection.ids" -test-iterations "$iterations" -run-tests-until-failure >"$log" 2>&1 &
pid=$!
trap 'stop; tally_reached; report_hung interrupted' INT TERM
start=$SECONDS
quiet_since=$SECONDS
seen=0
ended=exited
while sleep 1; kill -0 "$pid" 2>/dev/null; do
    progress=$(grep -c ' Test .* started' "$log")
    [ "$progress" -eq "$seen" ] || { seen=$progress; quiet_since=$SECONDS; }
    if [ $((SECONDS - quiet_since)) -ge "$stall" ]; then ended=stalled; break; fi
    if [ $((SECONDS - start)) -ge "$budget" ]; then ended=budget; break; fi
done
wall=$((SECONDS - start))
status=0
if [ "$ended" = exited ]; then wait "$pid" || status=$?; else stop; fi
trap - INT TERM
tally_reached
too_few="flake-guard: asked for $iterations iterations, the log shows $reached; see $log"

case $ended in
    stalled) report_hung "no progress for ${stall}s" ;;
    budget)
        stopped="flake-guard: stopped at the ${budget}s budget after $reached of $iterations repetitions; raise --budget to repeat more"
        echo "$stopped"
        [ "$reached" -ge 2 ] || { echo "$too_few" >&2; finish broken 65; }
        annotate "::warning title=flake guard stopped at its budget::$stopped"
        finish stopped 0
        ;;
esac

if [ "$status" -ne 0 ]; then
    # The Failing tests: block keeps the identifier form a display-named test hides; the awk's
    # names are the fallback for a run that died before xcodebuild printed it.
    awk '/^Failing tests:/ { block = 1; next } block && /^\t/ { sub(/^\t+/, ""); print; next } { block = 0 }' "$log" >"$run/failing.names"
    [ -s "$run/failing.names" ] || awk -v mode=failures -f scripts/test-log.awk "$log" >"$run/failing.names"
    awk -F'\t' "$base_name"'
        FILENAME == ARGV[1] { failed[base($0)] = 1; next }
        base($1) in failed { print $0 "\t" base($1) }' "$run/failing.names" "$run/reached.tsv" >"$run/failing.tsv"
    repetition=$(head -1 "$run/failing.tsv" | cut -f3)
    echo "flake-guard: FAILED on repetition ${repetition:-$reached} of $iterations under $load hogs; load1 now $(load1)"
    [ -s "$run/failing.tsv" ] || echo "  the run failed and named no test; see $log"
    while IFS=$'\t' read -r id declaration k _; do
        echo "  ✘ $id  $declaration"
        annotate "::error file=${declaration%:*},line=${declaration##*:},title=flaky under load::$id failed on repetition $k of $iterations under $load busy loops on $ncpu cores"
    done <"$run/failing.tsv"
    awk -f scripts/test-log-summary.awk "$log" | uniq
    cut -f4 "$run/failing.tsv" | sed 's/^/reproduce: scripts\/flake-hunt.sh --repetitions 200 /'
    finish failed 1
fi

# An identifier xcodebuild does not know runs nothing and exits 0, and a run that never repeated
# proves nothing about load, so a pass has to show both.
ran=$(awk -v mode=count -f scripts/test-log.awk "$log")
if [ "$ran" -lt "$selected" ]; then
    echo "flake-guard: selected $selected tests, the run reports $ran; see $log" >&2
    finish broken 65
fi
[ "$reached" -ge 2 ] || { echo "$too_few" >&2; finish broken 65; }
echo "flake-guard: passed; $selected tests x $reached repetitions under load in ${wall}s"
finish passed 0
