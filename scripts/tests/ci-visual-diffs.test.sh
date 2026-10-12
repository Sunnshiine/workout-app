#!/bin/bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_script="$script_dir/../ci-visual-diffs.sh"
[ -x "$source_script" ] || { echo "not executable: $source_script" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/gh" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$STUB_DIR/calls.log"
case "$1 $2" in
    "pr view")
        [ "${STUB_FORK:-}" = true ] && exit 0
        echo topic ;;
    "run list")
        shift 2
        jq_expr="" filters=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --jq) jq_expr=$2; shift 2 ;;
                --json | --limit) shift 2 ;;
                --workflow | --branch | --event) filters="$filters $1 $2"; shift 2 ;;
                *) echo "gh stub: unexpected flag $1" >&2; exit 1 ;;
            esac
        done
        [ "$filters" = " --workflow ci.yml --branch topic --event pull_request" ] \
            || { echo "gh stub: unexpected filters$filters" >&2; exit 1; }
        jq -r "$jq_expr" "$STUB_DIR/runs.json" ;;
    "run download")
        [ "$3" = "$STUB_RUN" ] || { echo "gh stub: no run $3" >&2; exit 1; }
        case "${STUB_ARTIFACT:-folder}" in
            other) echo "no artifact matches any of the names or patterns provided" >&2; exit 1 ;;
            none) echo "no valid artifacts found to download" >&2; exit 1 ;;
            error) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
            folder) mkdir -p "$7/VisualTests.xcresult"; touch "$7/VisualTests.xcresult/Info.plist" ;;
            flat) mkdir -p "$7"; touch "$7/Info.plist" ;;
        esac ;;
    *) echo "gh stub: unexpected command: $*" >&2; exit 1 ;;
esac
STUB
cat >"$root/bin/xcrun" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$STUB_DIR/calls.log"
[ "$1" = xcresulttool ] || { echo "xcrun stub: unexpected $*" >&2; exit 1; }
path="" out="" test=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
        --path) path=${args[i + 1]} ;;
        --output-path) out=${args[i + 1]} ;;
        --test-id) test=${args[i + 1]} ;;
    esac
done
[ -f "$path/Info.plist" ] || { echo "xcrun stub: $path is not a result bundle" >&2; exit 1; }
case "$2 $3 ${4:-}" in
    "export attachments "*) cp "$STUB_DIR"/attachments/* "$out"/ 2>/dev/null || true ;;
    "get test-results summary") cat "$STUB_DIR/summary.json" ;;
    "get test-results activities") cat "$STUB_DIR/activities/$(printf '%s' "$test" | tr '/()' '___').json" ;;
    *) echo "xcrun stub: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$root/bin/gh" "$root/bin/xcrun"

run=38165372006
repo="$root/repo"
case_dir="$root/case"
snap=Tests/Visual/__Snapshots__

# One fixture per case: a fake repo holding the script and two baselines, and a stub directory of
# attachments, a summary and per-test activities.
fresh() {
    rm -rf "$repo" "$case_dir"
    mkdir -p "$repo/scripts" "$repo/$snap/SessionViewVisualTests" "$case_dir/attachments" "$case_dir/activities"
    cp "$source_script" "$repo/scripts/"
    touch "$repo/Tests/Visual/SessionViewVisualTests.swift" "$repo/Tests/Visual/SettingsViewVisualTests.swift"
    echo old-day >"$repo/$snap/SessionViewVisualTests/day.1.png"
    echo old-night >"$repo/$snap/SessionViewVisualTests/night.1.png"
    : >"$case_dir/calls.log"
    printf '[{"databaseId": %s, "status": "completed", "conclusion": "failure", "headSha": "abcdef1234"}]\n' "$run" \
        >"$case_dir/runs.json"
    tests_json="[]"
}

# attachment NAME KEY: an attachment activity whose exported file holds "KEY".
attachment() {
    local uuid
    uuid=$(printf '%08X-0000-0000-0000-%012X' "$RANDOM$RANDOM" "$RANDOM")
    echo "$2" >"$case_dir/attachments/$uuid.png"
    jq -nc --arg n "${1%.png}_0_$uuid.png" --arg u "$uuid" \
        '{activityType: "com.apple.dt.xctest.activity-type.attachmentContainer", attachments: [{name: $n, uuid: $u}]}'
}

mismatch_issue() {
    jq -nc --arg p "$1" '{isAssociatedWithFailure: true, title: ("Issue recorded: Snapshot does not match reference.\n\n@−\n\"file:///Users/runner/work/workout-app/workout-app/Tests/Visual/__Snapshots__/" + $p + "\"\n@+\n\"file:///Users/runner/Library/Developer/CoreSimulator/Devices/X/data/tmp/" + $p + "\"\n\nNewly-taken snapshot does not match reference."), attachments: [{name: "Complete Issue Description.txt", uuid: "T"}]}'
}

missing_issue() {
    jq -nc '{isAssociatedWithFailure: true, title: "Issue recorded: No reference was found on disk. New snapshot was not recorded because recording is disabled"}'
}

other_issue() { jq -nc --arg t "$1" '{isAssociatedWithFailure: true, title: $t}'; }

# failing_test ID ACTIVITY...: one failing test whose single run recorded these activities in order.
failing_test() {
    local id=$1
    shift
    printf '%s\n' "$@" | jq -sc --arg id "$id" '{testIdentifier: $id, testRuns: [{activities: .}]}' \
        >"$case_dir/activities/$(printf '%s' "$id" | tr '/()' '___').json"
    tests_json=$(jq -c --arg id "$id" '. + [{testIdentifierString: $id, failureText: "x"}]' <<<"$tests_json")
}

two_mismatches() {
    failing_test "SessionViewVisualTests/day()" \
        "$(attachment reference.png ref-day)" "$(attachment failure.png runner-day)" \
        "$(attachment difference.png diff-day)" "$(mismatch_issue SessionViewVisualTests/day.1.png)"
    failing_test "SessionViewVisualTests/night()" \
        "$(attachment reference.png ref-night)" "$(attachment failure.png runner-night)" \
        "$(attachment difference.png diff-night)" "$(mismatch_issue SessionViewVisualTests/night.1.png)"
}

check() {
    local name=$1 want_status=$2 want_out=$3
    shift 3
    jq -nc --argjson f "$tests_json" '{testFailures: $f}' >"$case_dir/summary.json"
    STUB_DIR="$case_dir" STUB_RUN="$run" PATH="$root/bin:$PATH" "$repo/scripts/ci-visual-diffs.sh" "$@" \
        >"$case_dir/out" 2>"$case_dir/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && [ "$(cat "$case_dir/out")" = "$want_out" ]; then
        ok "$name"
    else
        bad "$name"
        printf 'want exit %s, stdout:\n%s\n' "$want_status" "$want_out" | sed 's/^/       /'
        printf 'got exit %s, stdout:\n%s\n' "$status" "$(cat "$case_dir/out")" | sed 's/^/       /'
        [ -s "$case_dir/err" ] && sed 's/^/       stderr: /' "$case_dir/err"
    fi
}

check_err() {
    if grep -qF -- "$2" "$case_dir/err"; then ok "$1"; else bad "$1: stderr was $(cat "$case_dir/err")"; fi
}

expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got '$2', want '$3'"; fi
}

out_dir="$repo/.build/ci-visual-diffs/$run"
listing() {
    local s
    for s in "$@"; do
        case "$s" in
            *'|nodiff') s=${s%|nodiff}; printf '%s\t%s\t\n' "$s" "$out_dir/snapshots/$s" ;;
            *) printf '%s\t%s\t%s\n' "$s" "$out_dir/snapshots/$s" "$out_dir/diffs/$s" ;;
        esac
    done
}

echo "listing"

fresh
two_mismatches
check "a run id lists each failing snapshot with its runner and difference images" 0 \
    "$(listing SessionViewVisualTests/day.1.png SessionViewVisualTests/night.1.png)" "$run"
expect "the runner image is the failure attachment" "$(cat "$out_dir/snapshots/SessionViewVisualTests/day.1.png")" runner-day
expect "the difference image is the difference attachment" "$(cat "$out_dir/diffs/SessionViewVisualTests/night.1.png")" diff-night
expect "listing leaves the baselines alone" "$(cat "$repo/$snap/SessionViewVisualTests/day.1.png")" old-day
check_err "listing names the count on stderr" "run $run: 2 failing snapshot(s) in $out_dir"

fresh
two_mismatches
STUB_ARTIFACT=flat check "a bundle uploaded alone, its contents at the artifact root, lists the same" 0 \
    "$(listing SessionViewVisualTests/day.1.png SessionViewVisualTests/night.1.png)" "$run"

fresh
failing_test "SessionViewVisualTests/both()" \
    "$(attachment reference.png r1)" "$(attachment failure.png first)" "$(attachment difference.png d1)" \
    "$(mismatch_issue SessionViewVisualTests/both.1.png)" \
    "$(attachment reference.png r2)" "$(attachment failure.png second)" "$(attachment difference.png d2)" \
    "$(mismatch_issue SessionViewVisualTests/both.dark.png)"
check "a test with two failing snapshots lists both" 0 \
    "$(listing SessionViewVisualTests/both.1.png SessionViewVisualTests/both.dark.png)" "$run"
expect "each issue owns the images recorded just before it" \
    "$(cat "$out_dir/snapshots/SessionViewVisualTests/both.1.png" "$out_dir/snapshots/SessionViewVisualTests/both.dark.png")" \
    "$(printf 'first\nsecond')"

fresh
failing_test "SettingsViewVisualTests/fresh()" "$(attachment fresh.1.png runner-fresh)" "$(missing_issue)"
check "a missing reference lists the runner's render with no difference image" 0 \
    "$(listing 'SettingsViewVisualTests/fresh.1.png|nodiff')" "$run"
check "--apply records a missing baseline in its suite's folder" 0 \
    "$snap/SettingsViewVisualTests/fresh.1.png" "$run" --apply fresh
expect "the new baseline holds the runner's render" "$(cat "$repo/$snap/SettingsViewVisualTests/fresh.1.png")" runner-fresh

fresh
rm "$repo/Tests/Visual/SettingsViewVisualTests.swift"
failing_test "SettingsViewVisualTests/fresh()" "$(attachment fresh.1.png runner-fresh)" "$(missing_issue)"
check "a missing reference whose suite has no same-named file exits 1" 1 "" "$run"
check_err "it names the file the folder must match" "Tests/Visual/SettingsViewVisualTests.swift"

fresh
failing_test "SessionViewVisualTests/layout()" "$(other_issue "Expectation failed: (gap → 3.0) == 0")"
check "a failure that is not a snapshot lists nothing and exits 0" 0 "" "$run"
check_err "it points at the other failures" "1 failure(s) that are not snapshot mismatches: $out_dir/other-failures.txt"
expect "the other failure is recorded with its test" "$(cat "$out_dir/other-failures.txt")" \
    "$(printf 'SessionViewVisualTests/layout()\tExpectation failed: (gap → 3.0) == 0')"

fresh
failing_test "SessionViewVisualTests/day()" "$(attachment reference.png r)" "$(mismatch_issue SessionViewVisualTests/day.1.png)"
check "a mismatch with no runner image exits 1" 1 "" "$run"
check_err "it names the snapshot" "SessionViewVisualTests/day() failed on SessionViewVisualTests/day.1.png"

fresh
failing_test "SessionViewVisualTests/both()" \
    "$(attachment failure.png first)" "$(mismatch_issue SessionViewVisualTests/both.1.png)" \
    "$(mismatch_issue SessionViewVisualTests/both.dark.png)"
check "a second issue never borrows the first issue's render" 1 "" "$run"
check_err "it names the second snapshot" "failed on SessionViewVisualTests/both.dark.png"

fresh
two_mismatches
mkdir -p "$out_dir.partial/stale" "$out_dir/stale"
check "a leftover partial or earlier download is replaced" 0 \
    "$(listing SessionViewVisualTests/day.1.png SessionViewVisualTests/night.1.png)" "$run"
expect "neither stale folder survives" "$(ls -d "$out_dir.partial" "$out_dir/stale" 2>/dev/null)" ""
check "a second call downloads again" 0 \
    "$(listing SessionViewVisualTests/day.1.png SessionViewVisualTests/night.1.png)" "$run"
expect "two calls made two downloads" "$(grep -c '^run download' "$case_dir/calls.log")" 2

echo "apply"

for name in SessionViewVisualTests/day.1.png day.1.png SessionViewVisualTests/day day 'day()'; do
    fresh
    two_mismatches
    check "--apply $name copies that snapshot's render" 0 "$snap/SessionViewVisualTests/day.1.png" "$run" --apply "$name"
    expect "--apply $name wrote the runner's render" "$(cat "$repo/$snap/SessionViewVisualTests/day.1.png")" runner-day
    expect "--apply $name left the other baseline" "$(cat "$repo/$snap/SessionViewVisualTests/night.1.png")" old-night
done

fresh
two_mismatches
check "--apply twice writes the same bytes" 0 "$snap/SessionViewVisualTests/day.1.png" "$run" --apply day
check "--apply twice, second call" 0 "$snap/SessionViewVisualTests/day.1.png" "$run" --apply day
expect "the baseline still holds the render" "$(cat "$repo/$snap/SessionViewVisualTests/day.1.png")" runner-day

fresh
two_mismatches
check "--apply with one unknown name writes nothing" 2 "" "$run" --apply day nope
check_err "it names the unknown name" "no failing snapshot matches nope"
expect "the matched baseline is untouched" "$(cat "$repo/$snap/SessionViewVisualTests/day.1.png")" old-day

fresh
check "--apply on a run with no failing snapshot exits 2" 2 "" "$run" --apply day

echo "runs and artifacts"

fresh
two_mismatches
jq -c --argjson r "$run" '. + [
    {databaseId: ($r + 1), status: "in_progress", conclusion: "", headSha: "1111111111"},
    {databaseId: ($r + 2), status: "completed", conclusion: "cancelled", headSha: "2222222222"},
    {databaseId: ($r + 3), status: "completed", conclusion: "skipped", headSha: "3333333333"},
    {databaseId: ($r - 9), status: "completed", conclusion: "success", headSha: "4444444444"}]' \
    "$case_dir/runs.json" >"$case_dir/runs.tmp" && mv "$case_dir/runs.tmp" "$case_dir/runs.json"
check "a PR number lists its newest finished run, past running, cancelled and skipped ones" 0 \
    "$(listing SessionViewVisualTests/day.1.png SessionViewVisualTests/night.1.png)" 881
check_err "it names the run it picked" "#881: newest finished CI run is $run, on abcdef12"

fresh
echo "[]" >"$case_dir/runs.json"
check "a PR with no finished CI run exits 3" 3 "" 881
check_err "it says so" "#881's branch topic has no finished CI run"

fresh
STUB_FORK=true check "a PR from a fork exits 1" 1 "" 881

fresh
STUB_ARTIFACT=other check "a run whose artifacts hold no visual-baseline-diffs exits 3" 3 "" "$run"
check_err "it says why there may be none" "its visual-tests job was green, skipped, or has not finished"

fresh
STUB_ARTIFACT=none check "a run with no artifact at all exits 3" 3 "" "$run"

fresh
STUB_ARTIFACT=error check "a failed download exits 1" 1 "" "$run"
check_err "it passes gh's error through" "HTTP 502: Bad Gateway"

echo "arguments"

fresh
check "no argument exits 2" 2 ""
check "a non-numeric target exits 2" 2 "" abc
check "--apply with no name exits 2" 2 "" "$run" --apply
check "a name without --apply exits 2" 2 "" "$run" day
check "an unknown flag exits 2" 2 "" "$run" --frobnicate
STUB_DIR="$case_dir" PATH="$root/bin:$PATH" "$repo/scripts/ci-visual-diffs.sh" --help >"$case_dir/out" 2>&1
expect "--help exits 0 and prints the usage" "$?:$(head -1 "$case_dir/out")" \
    "0:scripts/ci-visual-diffs.sh <run-id|PR> [--apply <name>...]"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
