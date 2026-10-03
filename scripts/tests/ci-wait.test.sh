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
frame="$STUB_DIR/frames/$(cat "$STUB_DIR/cursor").json"
sub="$1 $2"
shift 2
id="" jq_expr="." limit=20 commit="" workflow="" event="" fields=""
while [ $# -gt 0 ]; do
    case "$1" in
        --jq) jq_expr=$2; shift 2 ;;
        --limit) limit=$2; shift 2 ;;
        --commit) commit=$2; shift 2 ;;
        --workflow) workflow=$2; shift 2 ;;
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
        if [[ "$id" =~ ^[0-9]{7,}$ ]]; then echo "GraphQL: Could not resolve to a PullRequest with the number of $id." >&2; exit 1; fi
        if [[ "$id" == main || "$id" =~ ^[0-9a-f]{7,40}$ ]]; then echo "no pull requests found for branch \"$id\"" >&2; exit 1; fi
        jq -nr --arg s "$STUB_SHA" '{headRefOid: $s}' | jq -r "$jq_expr" ;;
    "api repos/{owner}/{repo}/commits/"*) jq -nr --arg s "$STUB_SHA" '{sha: $s}' | jq -r "$jq_expr" ;;
    "api repos/{owner}/{repo}/actions/runs/"*/jobs)
        [[ "$sub" =~ /([0-9]+)/jobs$ ]]
        jq -e --argjson id "${BASH_REMATCH[1]}" '.[] | select(.databaseId == $id) | {jobs: [.jobs[] | {id}]}' \
            "$frame" >"$STUB_DIR/jobs.json" || { echo "gh stub: no run ${BASH_REMATCH[1]}" >&2; exit 1; }
        jq -r "$jq_expr" "$STUB_DIR/jobs.json" ;;
    "api repos/{owner}/{repo}/check-runs/"*/annotations)
        [[ "$sub" =~ /([0-9]+)/annotations$ ]]
        jq -e --argjson id "${BASH_REMATCH[1]}" '[.[].jobs[] | select(.id == $id)][0] | (.annotations // []) | map({message: .})' \
            "$frame" >"$STUB_DIR/annotations.json" || { echo "gh stub: no job ${BASH_REMATCH[1]}" >&2; exit 1; }
        jq -r "$jq_expr" "$STUB_DIR/annotations.json" ;;
    "run list")
        for f in ${fields//,/ }; do
            case "$f" in
                databaseId | workflowName | event | status | conclusion | headSha | createdAt | updatedAt) ;;
                *) echo "gh stub: gh run list has no JSON field $f" >&2; exit 1 ;;
            esac
        done
        jq --arg c "$commit" --arg s "$STUB_SHA" --arg w "$workflow" --arg e "$event" \
            "map(select((\$c == \"\" or (.headSha // \$s) == \$c) and (\$w == \"\" or .workflowName == \$w)
                        and (\$e == \"\" or .event == \$e))) | .[:$limit]" \
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

run_record() {
    local id=$1 status=$2 conclusion=$3
    shift 3
    [ $# -gt 0 ] || set -- swift-tests lint visual-tests
    workflow_run CI pull_request "$id" "$status" "$conclusion" "$@"
}

workflow_run() {
    local workflow=$1 event=$2 id=$3 status=$4 conclusion=$5
    shift 5
    jq -nc --arg w "$workflow" --arg e "$event" --argjson id "$id" --arg s "$status" --arg c "$conclusion" \
        '{databaseId: $id, workflowName: $w, event: $e, status: $s, conclusion: $c,
          jobs: [$ARGS.positional | to_entries[] | {id: ($id * 100 + .key), name: .value, conclusion: $c}]}' --args "$@"
}

by_concurrency() {
    jq -c '.jobs[0].annotations = ["Canceling since a higher priority waiting request for \(.workflowName) exists"]' <<<"$1"
}

jobless() { jq -c '.jobs = []' <<<"$1"; }

check() {
    local name=$1 want_status=$2 want_out=$3 arg=$4
    shift 4
    local dir="$root/case"
    rm -rf "$dir"
    mkdir -p "$dir/frames"
    local i=0
    for f in "$@"; do printf '%s\n' "$f" >"$dir/frames/$i.json"; i=$((i + 1)); done
    echo 0 >"$dir/cursor"
    : >"$dir/calls.log"
    STUB_DIR="$dir" STUB_SHA="$sha" STUB_PR_ERROR="${pr_error:-}" PATH="$root/bin:$PATH" "$ci_wait" "$arg" >"$dir/out" 2>"$dir/err"
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

# Frames list runs in the API's order: newest createdAt first, lower id first on a tie.
A=35742049156
B=35742049318
C=35742049999

success_b="CI success on 73b27aa (run $B)
  visual-tests: success
  swift-tests: success
  lint: success"

check "#680 live order: same-second duplicates list the cancelled run first" 0 "$success_b" 668 \
    "[$(by_concurrency "$(run_record $A completed cancelled)"), $(run_record $B in_progress "" visual-tests swift-tests lint)]" \
    "[$(by_concurrency "$(run_record $A completed cancelled)"), $(run_record $B completed success visual-tests swift-tests lint)]"

check "#680 race: the duplicate cancels the run the first poll found" 0 "$success_b" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress "" visual-tests swift-tests lint), $(by_concurrency "$(run_record $A completed cancelled)")]" \
    "[$(run_record $B completed success visual-tests swift-tests lint), $(by_concurrency "$(run_record $A completed cancelled)")]"

check "a second retarget cancels the run that replaced the first" 0 "CI success on 73b27aa (run $C)
  swift-tests: success
  lint: success
  visual-tests: success" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress ""), $(by_concurrency "$(run_record $A completed cancelled)")]" \
    "[$(run_record $C in_progress ""), $(by_concurrency "$(run_record $B completed cancelled)"), $(by_concurrency "$(run_record $A completed cancelled)")]" \
    "[$(run_record $C completed success), $(by_concurrency "$(run_record $B completed cancelled)"), $(by_concurrency "$(run_record $A completed cancelled)")]"

check "the run that replaced a cancelled one fails" 1 "CI failure on 73b27aa (run $B)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress ""), $(by_concurrency "$(run_record $A completed cancelled)")]" \
    "[$(run_record $B completed failure), $(by_concurrency "$(run_record $A completed cancelled)")]"

check "a newer run that starts after the watched run failed decides" 0 "CI success on 73b27aa (run $B)
  swift-tests: success
  lint: success
  visual-tests: success" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress ""), $(run_record $A completed failure)]" \
    "[$(run_record $B completed success), $(run_record $A completed failure)]"

check "an older green run does not rescue a cancelled newest run" 1 "CI cancelled on 73b27aa (run $B)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(run_record $B completed cancelled), $(run_record $A completed success)]"

check "a cancelled run with no newer run on the commit reports cancelled" 1 "CI cancelled on 73b27aa (run $A)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed cancelled)]"

check "a single run that succeeds" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed success)]"

check "a single run that fails" 1 "CI failure on 73b27aa (run $A)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed failure)]"

check "a run that appears after two polls" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success" main \
    "[]" "[]" \
    "[$(workflow_run CI push $A in_progress "" swift-tests lint visual-tests)]" \
    "[$(workflow_run CI push $A completed success swift-tests lint visual-tests)]"

check "a commit that never gets a run exits 3" 3 "" 668 "[]"
if [ "$(cat "$root/case/err")" = "no pull_request workflow ran on 73b27aa within 5 minutes" ]; then
    ok "a commit that never gets a run names the event it searched"
else
    bad "a commit that never gets a run: stderr was $(cat "$root/case/err")"
fi

L=37087587279

check "#796: a red check from another workflow fails a PR that CI skipped" 1 "Workflow lint failure on 73b27aa (run $L)
  skill-links: failure" 795 \
    "[$(workflow_run "Workflow lint" pull_request $L completed failure skill-links)]"

check "#796: a red check from another workflow fails a PR whose CI is green" 1 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
Workflow lint failure on 73b27aa (run $L)
  skill-links: failure" 795 \
    "[$(workflow_run "Workflow lint" pull_request $L completed failure skill-links), $(run_record $A completed success)]"

check "#796: a PR whose only workflow is not CI and passes succeeds" 0 "Workflow lint success on 73b27aa (run $L)
  skill-links: success" 795 \
    "[$(workflow_run "Workflow lint" pull_request $L in_progress "" skill-links)]" \
    "[$(workflow_run "Workflow lint" pull_request $L completed success skill-links)]"

V=35742049109
W=35742049659

check "PR 668 live: each workflow's cancelled duplicate loses to its newer run" 0 "CI success on 73b27aa (run $B)
  swift-tests: success
  lint: success
  visual-tests: success
Verify tools success on 73b27aa (run $W)
  sheet: success
  tree: success" 668 \
    "[$(run_record $B completed success), $(by_concurrency "$(workflow_run "Verify tools" pull_request $V completed cancelled sheet tree)"), $(workflow_run "Verify tools" pull_request $W completed success sheet tree), $(by_concurrency "$(run_record $A completed cancelled)")]"

check "a queued replacement is waited on, not hidden behind the run it cancelled" 0 "$success_b" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B queued "" visual-tests swift-tests lint), $(by_concurrency "$(run_record $A completed cancelled)")]" \
    "[$(run_record $B completed success visual-tests swift-tests lint), $(by_concurrency "$(run_record $A completed cancelled)")]"

check "a workflow still running after CI finished decides" 1 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
Verify tools failure on 73b27aa (run $W)
  sheet: failure
  tree: failure" 668 \
    "[$(run_record $A in_progress ""), $(workflow_run "Verify tools" pull_request $W in_progress "" sheet tree)]" \
    "[$(run_record $A completed success), $(workflow_run "Verify tools" pull_request $W in_progress "" sheet tree)]" \
    "[$(run_record $A completed success), $(workflow_run "Verify tools" pull_request $W completed failure sheet tree)]"

check "a skipped run that cancelled a build supersedes it" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
testflight-pr superseded on 73b27aa (run $B)
  build: cancelled" 668 \
    "[$(workflow_run testflight-pr pull_request $C completed skipped build), $(by_concurrency "$(workflow_run testflight-pr pull_request $B completed cancelled build)"), $(run_record $A completed success)]"

check "a PR whose only runs were skipped exits 3" 3 "" 788 \
    "[$(workflow_run testflight-pr pull_request $A completed skipped build)]"

issue_runs="$(workflow_run "Agent Implement" issues $((C + 2)) in_progress "" implement), $(workflow_run "Agent To Issues PRD" issues $((C + 1)) completed failure to-issues), "
check "main answers for its push runs, not the issues-event agent runs on its head" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
TestFlight Stable success on 73b27aa (run $B)
  archive: success
  upload: success" main \
    "[${issue_runs}$(workflow_run CI push $A in_progress "" swift-tests lint visual-tests), $(workflow_run "TestFlight Stable" push $B in_progress "" archive upload)]" \
    "[${issue_runs}$(workflow_run CI push $A completed success swift-tests lint visual-tests), $(workflow_run "TestFlight Stable" push $B in_progress "" archive upload)]" \
    "[${issue_runs}$(workflow_run CI push $A completed success swift-tests lint visual-tests), $(workflow_run "TestFlight Stable" push $B completed success archive upload)]"

check "a failed build is not erased by a later skipped run of its workflow" 1 "TestFlight PR failure on 73b27aa (run $B)
  build: failure" 505 \
    "[$(workflow_run "TestFlight PR" pull_request $C completed skipped build), $(workflow_run "TestFlight PR" pull_request $B completed failure build)]"

later_merge="$(workflow_run "TestFlight Stable" push $C in_progress "" archive upload | jq -c '.headSha = "later"')"
for target in main 999b783; do
    check "on $target, a run cancelled for concurrency is superseded, not failed" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
TestFlight Stable superseded on 73b27aa (run $B)
  archive: cancelled
  upload: cancelled" "$target" \
        "[$later_merge, $(workflow_run CI push $A completed success swift-tests lint visual-tests), $(by_concurrency "$(workflow_run "TestFlight Stable" push $B completed cancelled archive upload)")]"
done

later_ci="$(workflow_run CI push $C in_progress "" swift-tests lint visual-tests | jq -c '.headSha = "later" | .createdAt = "2026-09-24T00:03:30Z"')"
check "on main, a run cancelled by hand fails though a later merge's run overlapped it" 1 "CI cancelled on 73b27aa (run $B)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" main \
    "[$later_ci, $(workflow_run CI push $B completed cancelled swift-tests lint visual-tests | jq -c '.updatedAt = "2026-09-24T00:04:02Z"')]"

check "a PR's build cancelled by hand fails though a later run skipped" 1 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
TestFlight PR cancelled on 73b27aa (run $B)
  build: cancelled" 505 \
    "[$(workflow_run "TestFlight PR" pull_request $C completed skipped build), $(workflow_run "TestFlight PR" pull_request $B completed cancelled build), $(run_record $A completed success)]"

check "a PR's newest run cancelled for concurrency fails, since the head moved on" 1 "CI cancelled on 73b27aa (run $B)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(by_concurrency "$(run_record $B completed cancelled)"), $(run_record $A completed success)]"

check "a run cancelled while queued, with no jobs, is superseded by its newer run" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success
testflight-pr superseded on 73b27aa (run $B)" 668 \
    "[$(workflow_run testflight-pr pull_request $C completed skipped build), $(jobless "$(workflow_run testflight-pr pull_request $B completed cancelled build)"), $(run_record $A completed success)]"

pr_error="HTTP 502: Bad Gateway (https://api.github.com/graphql)" check "a gh pr view failure that is not 'no PR' exits 1" 1 "" 668 \
    "[$(workflow_run CI push $A completed success swift-tests lint visual-tests)]"
if grep -q "HTTP 502: Bad Gateway" "$root/case/err" && ! grep -q "^api repos/{owner}/{repo}/commits/" "$root/case/calls.log"; then
    ok "a gh pr view failure is reported and never looks the target up as a commit"
else
    bad "a gh pr view failure: stderr was $(cat "$root/case/err"), calls were $(cat "$root/case/calls.log")"
fi

check "an all-digit short SHA falls back to the commit and its push runs" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success" 2692824 \
    "[$(run_record $B completed failure), $(workflow_run CI push $A completed success swift-tests lint visual-tests)]"

check "a failed build is not erased by a cancelled retry and a later skipped run" 1 "TestFlight PR failure on 73b27aa (run $A)
  build: failure" 505 \
    "[$(workflow_run "TestFlight PR" pull_request $C completed skipped build), $(by_concurrency "$(workflow_run "TestFlight PR" pull_request $B completed cancelled build)"), $(workflow_run "TestFlight PR" pull_request $A completed failure build)]"

check "a PR named by its branch answers for its pull_request runs" 0 "$success_b" fix/retro-ciwait \
    "[$(run_record $B completed success visual-tests swift-tests lint)]"

other_pr="$(run_record $C completed success | jq -c '.headSha = "other-pr"')"
check "a PR's cancelled run fails even when another PR ran its workflow since" 1 "CI cancelled on 73b27aa (run $A)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$other_pr, $(run_record $A completed cancelled)]"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
