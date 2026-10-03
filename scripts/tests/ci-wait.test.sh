#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ci_wait="$script_dir/../ci-wait.sh"
[ -x "$ci_wait" ] || { echo "not executable: $ci_wait" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

sha=73b27aad97eff49511b45cf10e614f1d6b72e46b
pushed=f2c0ffee00000000000000000000000000000002

cat >"$root/bin/next-frame" <<'STUB'
#!/usr/bin/env bash
next=$(( $(cat "$STUB_DIR/cursor") + 1 ))
[ -f "$STUB_DIR/frames/$next.json" ] && echo "$next" >"$STUB_DIR/cursor"
exit 0
STUB
cat >"$root/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$(wc -l <"$STUB_DIR/calls.log")" -lt 200 ] || { echo "gh stub: 200 calls, ci-wait.sh is looping" >&2; exit 99; }
printf '%s\n' "${*//$'\n'/ }" >>"$STUB_DIR/calls.log"
cursor=$(cat "$STUB_DIR/cursor")
frame="$STUB_DIR/frames/$cursor.json"
sub="$1 $2"
shift 2
id="" jq_expr="." limit=20 commit="" event="" fields=""
while [ $# -gt 0 ]; do
    case "$1" in
        --jq) jq_expr=$2; shift 2 ;;
        --limit) limit=$2; shift 2 ;;
        --commit) commit=$2; shift 2 ;;
        --event) event=$2; shift 2 ;;
        --json) fields=$2; shift 2 ;;
        --interval) shift 2 ;;
        -*) echo "gh stub: unexpected flag $1" >&2; exit 1 ;;
        *) id=$1; shift ;;
    esac
done
case "$sub" in
    "pr view")
        if [ -n "${STUB_PR_ERROR:-}" ]; then echo "$STUB_PR_ERROR" >&2; exit 1; fi
        head=$STUB_SHA
        [ -f "$STUB_DIR/head.$cursor" ] && head=$(cat "$STUB_DIR/head.$cursor")
        jq -nr --arg s "$head" '{headRefOid: $s}' | jq -r "$jq_expr" ;;
    "run list")
        for f in ${fields//,/ }; do
            case "$f" in
                databaseId | workflowName | event | status | conclusion | headSha | createdAt | updatedAt) ;;
                *) echo "gh stub: gh run list has no JSON field $f" >&2; exit 1 ;;
            esac
        done
        jq --arg c "$commit" --arg s "$STUB_SHA" --arg e "$event" \
            "map(select((\$c == \"\" or (.headSha // \$s) == \$c) and (\$e == \"\" or .event == \$e))) | .[:$limit]" \
            "$frame" | jq -r "$jq_expr" ;;
    "run watch") next-frame ;;
    "run view")
        jq -e --argjson id "$id" '.[] | select(.databaseId == $id)' "$frame" >"$STUB_DIR/view.json" \
            || { echo "gh stub: no run $id" >&2; exit 1; }
        jq -r "$jq_expr" "$STUB_DIR/view.json" ;;
    *) echo "gh stub: unexpected command: $sub $*" >&2; exit 1 ;;
esac
STUB
cat >"$root/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exec next-frame
STUB
chmod +x "$root/bin/next-frame" "$root/bin/gh" "$root/bin/sleep"

workflow_run() {
    local workflow=$1 id=$2 status=$3 conclusion=$4
    shift 4
    jq -nc --arg w "$workflow" --argjson id "$id" --arg s "$status" --arg c "$conclusion" \
        '{databaseId: $id, workflowName: $w, event: "pull_request", status: $s, conclusion: $c,
          jobs: [$ARGS.positional | to_entries[] | {id: ($id * 100 + .key), name: .value, conclusion: $c}]}' --args "$@"
}

ci() { workflow_run CI "$1" "$2" "$3" swift-tests lint visual-tests; }

on_pushed() { jq -c --arg s "$pushed" '.headSha = $s' <<<"$1"; }

# Each frame argument is one gh run list answer; gh run watch and sleep advance to the next.
# heads="a b c" makes gh pr view answer a in frame 0, b in frame 1, and so on.
check() {
    local name=$1 want_status=$2 want_out=$3 arg=$4
    shift 4
    local dir="$root/case" i=0 h
    rm -rf "$dir"
    mkdir -p "$dir/frames"
    for f in "$@"; do printf '%s\n' "$f" >"$dir/frames/$i.json"; i=$((i + 1)); done
    i=0
    for h in ${heads:-}; do echo "$h" >"$dir/head.$i"; i=$((i + 1)); done
    echo 0 >"$dir/cursor"
    : >"$dir/calls.log"
    STUB_DIR="$dir" STUB_SHA="$sha" STUB_PR_ERROR="${pr_error:-}" PATH="$root/bin:$PATH" "$ci_wait" ${arg:+"$arg"} >"$dir/out" 2>"$dir/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && [ "$(cat "$dir/out")" = "$want_out" ]; then
        ok "$name"
    else
        bad "$name"
        printf 'want exit %s, stdout:\n%s\n' "$want_status" "$want_out" | sed 's/^/       /'
        printf 'got exit %s, stdout:\n%s\n' "$status" "$(cat "$dir/out")" | sed 's/^/       /'
        [ -s "$dir/err" ] && sed 's/^/       stderr: /' "$dir/err"
        sed 's/^/       gh /' "$dir/calls.log"
    fi
}

check_err() {
    if [ "$(cat "$root/case/err")" = "$2" ]; then ok "$1"; else bad "$1: stderr was $(cat "$root/case/err")"; fi
}

# Frames list runs in the API's order: newest createdAt first, lower id first on a tie.
A=35742049156
B=35742049318
C=35742049999
L=37087587279
V=35742049109
W=35742049659
merge="gh pr merge 668 --squash --match-head-commit $sha"

ci_a_success="CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success"
ci_b_success="CI success on 73b27aa (run $B)
  swift-tests: success
  lint: success
  visual-tests: success"

echo "green: exit 0 and the pinned merge command"

check "a run that succeeds" 0 "$ci_a_success
$merge" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $A completed success)]"

check "a run that appears after two polls" 0 "$ci_a_success
$merge" 668 \
    "[]" "[]" \
    "[$(ci $A in_progress "")]" \
    "[$(ci $A completed success)]"

check "#680: a same-second duplicate's newer run decides over the cancelled one" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A completed cancelled), $(ci $B in_progress "")]" \
    "[$(ci $A completed cancelled), $(ci $B completed success)]"

check "#680: the duplicate cancels the run the first poll found" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $B queued ""), $(ci $A completed cancelled)]" \
    "[$(ci $B completed success), $(ci $A completed cancelled)]"

check "PR 668 live: each workflow's cancelled duplicate loses to its newer run" 0 "$ci_b_success
Verify tools success on 73b27aa (run $W)
  sheet: success
  tree: success
$merge" 668 \
    "[$(ci $B completed success), $(workflow_run "Verify tools" $V completed cancelled sheet tree), $(workflow_run "Verify tools" $W completed success sheet tree), $(ci $A completed cancelled)]"

check "a re-run that passes after the watched run failed decides" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $B in_progress ""), $(ci $A completed failure)]" \
    "[$(ci $B completed success), $(ci $A completed failure)]"

check "a run waiting on environment approval is waited on" 0 "$ci_a_success
$merge" 668 \
    "[$(ci $A waiting "")]" \
    "[$(ci $A completed success)]"

check "#796: a PR whose only workflow is not CI and passes succeeds" 0 "Workflow lint success on 73b27aa (run $L)
  skill-links: success
$merge" 668 \
    "[$(workflow_run "Workflow lint" $L in_progress "" skill-links)]" \
    "[$(workflow_run "Workflow lint" $L completed success skill-links)]"

check "a skipped run of another workflow is not read" 0 "$ci_a_success
$merge" 668 \
    "[$(workflow_run "TestFlight PR" $C completed skipped archive upload), $(ci $A completed success)]"

echo "red or unfinished: never exit 0"

check "a run that fails" 1 "CI failure on 73b27aa (run $A)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $A completed failure)]"

check "#796: a red check from another workflow fails a PR that CI skipped" 1 "Workflow lint failure on 73b27aa (run $L)
  skill-links: failure" 795 \
    "[$(workflow_run "Workflow lint" $L completed failure skill-links)]"

check "#796: a red check from another workflow fails a PR whose CI is green" 1 "$ci_a_success
Workflow lint failure on 73b27aa (run $L)
  skill-links: failure" 795 \
    "[$(workflow_run "Workflow lint" $L completed failure skill-links), $(ci $A completed success)]"

check "a workflow still running after CI finished decides" 1 "$ci_a_success
Verify tools failure on 73b27aa (run $W)
  sheet: failure
  tree: failure" 668 \
    "[$(ci $A in_progress ""), $(workflow_run "Verify tools" $W in_progress "" sheet tree)]" \
    "[$(ci $A completed success), $(workflow_run "Verify tools" $W in_progress "" sheet tree)]" \
    "[$(ci $A completed success), $(workflow_run "Verify tools" $W completed failure sheet tree)]"

check "a queued run cancelled by hand fails" 1 "CI cancelled on 73b27aa (run $A)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(ci $A queued "")]" \
    "[$(ci $A completed cancelled)]"

check "an older green run does not rescue a cancelled newest run" 1 "CI cancelled on 73b27aa (run $B)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(ci $B completed cancelled), $(ci $A completed success)]"

check "a failed build is not erased by a later skipped run" 1 "TestFlight PR failure on 73b27aa (run $B)
  build: failure" 668 \
    "[$(workflow_run "TestFlight PR" $C completed skipped build), $(workflow_run "TestFlight PR" $B completed failure build)]"

check "a build cancelled before it finished fails though a later run skipped" 1 "$ci_a_success
TestFlight PR cancelled on 73b27aa (run $B)
  build: cancelled" 668 \
    "[$(workflow_run "TestFlight PR" $C completed skipped build), $(workflow_run "TestFlight PR" $B completed cancelled build), $(ci $A completed success)]"

check "a run that needs approval to start fails" 1 "CI action_required on 73b27aa (run $A)
  swift-tests: action_required
  lint: action_required
  visual-tests: action_required" 668 \
    "[$(ci $A completed action_required)]"

check "a workflow that failed to start fails" 1 "$ci_a_success
Workflow lint startup_failure on 73b27aa (run $L)" 668 \
    "[$(ci $A completed success), $(jq -c '.jobs = []' <<<"$(workflow_run "Workflow lint" $L completed startup_failure)")]"

echo "head moved: never vouch for a head it did not watch"

heads="$sha $pushed $pushed" check "a push that cancels nothing on the watched head, onto a red head, fails" 1 "" 668 \
    "[$(ci $A completed success), $(workflow_run "TestFlight PR" $B in_progress "" archive upload)]" \
    "[$(on_pushed "$(ci $C in_progress "")"), $(ci $A completed success), $(workflow_run "TestFlight PR" $B in_progress "" archive upload)]" \
    "[$(on_pushed "$(ci $C completed failure)"), $(ci $A completed success), $(workflow_run "TestFlight PR" $B completed success archive upload)]"
check_err "a moved head names both commits" "the head of #668 moved from 73b27aa to f2c0ffe during the wait; run ci-wait.sh 668 again"

heads="$sha $pushed" check "a push that cancels the watched run fails" 1 "" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(on_pushed "$(ci $B in_progress "")"), $(ci $A completed cancelled)]"

heads="$sha $sha $pushed" check "a push during a wait that found no run fails instead of exiting 3" 1 "" 668 \
    "[]" "[]" "[$(on_pushed "$(ci $B in_progress "")")]"

echo "no run: exit 3"

check "a PR that starts no run exits 3" 3 "$merge" 668 "[]"
check_err "a PR that starts no run names the commit it searched" "no pull_request workflow ran on 73b27aa within 5 minutes"

check "a PR whose only runs were skipped exits 3" 3 "$merge" 668 \
    "[$(workflow_run "TestFlight PR" $A completed skipped build), $(workflow_run "Verify tools" $W completed skipped sheet)]"

echo "arguments"

for arg in "" main fix/retro-ciwait 999b783; do
    check "'$arg' is not a PR number and exits 2" 2 "" "$arg" "[$(ci $A completed success)]"
done

pr_error="HTTP 502: Bad Gateway (https://api.github.com/graphql)" check "a gh pr view failure exits 1" 1 "" 668 \
    "[$(ci $A completed success)]"
check_err "a gh pr view failure prints gh's error" "HTTP 502: Bad Gateway (https://api.github.com/graphql)"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
