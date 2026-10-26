#!/bin/bash
set -uo pipefail

usage() {
    cat <<'EOF'
scripts/ui-suite.sh --xctestrun FILE --destination DEST [--sla S] [--cap S] [--out DIR] [-- XCODEBUILD-ARG ...]

Runs WorkoutTrackerUITests with test-without-building from FILE on DEST, with every argument
after -- passed to xcodebuild, and times it from launch to exit.

  --sla S   the time the suite should take (default 600). A slower run passes, prints a
            hill-climb message naming its slowest tests, and under GitHub Actions annotates it
            and adds it to the job summary.
  --cap S   the time it may take (default 900). At the cap the run is stopped and fails, naming
            each test still running and how many finished.
  --out DIR where the log and UITests.xcresult go (default .build/ui-suite).

The last line is the status line:
  ui-suite: result=<passed|failed|capped|broken> wall=<s> sla=<s> cap=<s> passed=<n> failed=<n> skipped=<n> exit=<e>

Exits 0 when every test passed, 1 when a test failed or the cap stopped the run, 2 on a usage
error, and 65 when xcodebuild ran no test.
EOF
}

xctestrun="" destination="" sla=600 cap=900 out=.build/ui-suite
while [ $# -gt 0 ]; do
    case $1 in
        -h | --help) usage; exit 0 ;;
        --) shift; break ;;
        --xctestrun | --destination | --sla | --cap | --out) [ $# -ge 2 ] || { usage >&2; exit 2; } ;;
        *) usage >&2; exit 2 ;;
    esac
    case $1 in
        --xctestrun) xctestrun=$2 ;;
        --destination) destination=$2 ;;
        --sla) sla=$2 ;;
        --cap) cap=$2 ;;
        --out) out=$2 ;;
    esac
    shift 2
done
[ -n "$xctestrun" ] && [ -n "$destination" ] || { usage >&2; exit 2; }
for number in "$sla" "$cap"; do
    case $number in '' | *[!0-9]*) usage >&2; exit 2 ;; esac
done

mkdir -p "$out"
log=$out/ui-suite.log
bundle=$out/UITests.xcresult
rm -rf "$bundle"
annotate() { [ "${GITHUB_ACTIONS:-}" != true ] || echo "$1"; }
summarize() { [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"; }

passed=- failed=- skipped=-
finish() {
    echo "ui-suite: result=$1 wall=$wall sla=$sla cap=$cap passed=$passed failed=$failed skipped=$skipped exit=$2"
    exit "$2"
}

# Serial runs log "Test Case '-[Module.Class test]' started."; parallel runs log
# "Test case 'Class.test()' started on 'Clone 1 of ...'". Both reduce to Class/test.
names='function name(s) {
    if (match(s, /-\[[^ ]+ [^]]+\]/)) { s = substr(s, RSTART + 2, RLENGTH - 3); sub(/^[^.]*\./, "", s); sub(/ /, "/", s); return s }
    if (match(s, /Test case .[^ ]+\(\)/)) { s = substr(s, RSTART + 11, RLENGTH - 13); sub(/\./, "/", s); return s }
    return "" }'
unfinished() {
    awk "$names"'
        / started( on |\.$)/ { n = name($0); if (n != "") running[n] = 1; next }
        / (passed|failed|skipped)( on | \()/ { n = name($0); if (n != "") { delete running[n]; done++ } }
        END { for (n in running) print n; print done + 0 > "/dev/stderr" }' "$log"
}

echo "ui-suite: log $log, sla ${sla}s, cap ${cap}s"
xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$destination" \
    -only-testing:WorkoutTrackerUITests -resultBundlePath "$bundle" -collect-test-diagnostics never \
    "$@" >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null' EXIT
start=$SECONDS
ended=exited
while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$cap" ]; then ended=capped; break; fi
    sleep 1
done
wall=$((SECONDS - start))
status=0
if [ "$ended" = capped ]; then
    unfinished >"$out/unfinished" 2>"$out/finished"
    kill -TERM "$pid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    message="The UI suite reached its ${cap}s cap with $(cat "$out/finished") tests finished and was stopped."
    echo "ui-suite: $message Still running:"
    sed 's/^/  ✘ /' "$out/unfinished"
    [ -s "$out/unfinished" ] || echo "  no test was running; see $log"
    annotate "::error title=UI suite hit its ${cap}s cap::$message Still running: $(paste -sd' ' "$out/unfinished")"
    summarize "### UI suite stopped at its ${cap}s cap"$'\n\n'"$message Still running: $(paste -sd' ' "$out/unfinished")"
    finish capped 1
fi
wait "$pid" || status=$?
trap - EXIT

report=$out/tests.json
xcrun xcresulttool get test-results tests --path "$bundle" --compact >"$report" 2>/dev/null
# One line of counts, then the five slowest tests, one per line.
python3 -I - "$report" >"$out/results" <<'EOF'
import json, sys
counts = dict(Passed=0, Failed=0, Skipped=0)
cases = []
def walk(node):
    if node.get("nodeType") == "Test Case":
        result = "Passed" if node.get("result") == "Expected Failure" else node.get("result")
        counts[result if result in counts else "Failed"] += 1
        cases.append((node.get("durationInSeconds") or 0, node.get("nodeIdentifier", node.get("name"))))
    for child in node.get("children", []):
        walk(child)
try:
    for node in json.load(open(sys.argv[1])).get("testNodes", []):
        walk(node)
except Exception:
    print("- - -")
    sys.exit()
print(counts["Passed"], counts["Failed"], counts["Skipped"])
for seconds, name in sorted(cases, reverse=True)[:5]:
    print(f"{seconds:6.1f}s  {name}")
EOF
read -r passed failed skipped <"$out/results"
slowest=$(tail -n +2 "$out/results")

if [ "$wall" -gt "$sla" ]; then
    message="The UI suite took ${wall}s, over its ${sla}s SLA. Hill-climb UI test speed before adding more UI tests: shorten or split the slowest tests below, replace waits on real time with fixtures, and see docs/testing/ui-suite-time.md."
    echo "ui-suite: $message"
    echo "$slowest" | sed 's/^/  /'
    annotate "::warning title=UI suite over its ${sla}s SLA::$message Slowest: $(echo "$slowest" | head -3 | sed 's/^ *//' | paste -sd';' -)"
    summarize "### UI suite over its ${sla}s SLA"$'\n\n'"$message"$'\n\n```\n'"$slowest"$'\n```'
fi

case $passed in -) echo "ui-suite: no readable result in $bundle; see $log" >&2; finish broken 65 ;; esac
if [ "$status" -ne 0 ] || [ "$failed" -gt 0 ]; then
    "$(dirname "$0")/test-log-summary.sh" --cause "$log"
    finish failed 1
fi
[ "$passed" -gt 0 ] || { echo "ui-suite: no test ran; see $log" >&2; finish broken 65; }
finish passed 0
