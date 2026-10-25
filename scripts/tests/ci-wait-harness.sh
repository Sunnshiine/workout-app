# shellcheck shell=bash
# shellcheck disable=SC2034  # the test files that source this read these
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
branch_tip() { cat "$STUB_DIR/head.$cursor" 2>/dev/null || echo "$STUB_SHA"; }
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
        --interval | -f | -F) shift 2 ;;
        -*) echo "gh stub: unexpected flag $1" >&2; exit 1 ;;
        *) id=$1; shift ;;
    esac
done
case "$sub" in
    "pr view")
        if [ -n "${STUB_PR_ERROR:-}" ]; then echo "$STUB_PR_ERROR" >&2; exit 1; fi
        jq -nr --arg s "$STUB_SHA" '{headRefName: "topic", headRefOid: $s, isCrossRepository: ($ENV.STUB_FORK == "true"), body: "Reverts #12"}' | jq -r "$jq_expr" ;;
    "api repos/{owner}/{repo}/git/ref/heads/topic")
        jq -nr --arg s "$(branch_tip)" '{object: {sha: $s}}' | jq -r "$jq_expr" ;;
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
    "api graphql")
        if [ -n "${STUB_GRAPHQL_ERROR:-}" ]; then echo "$STUB_GRAPHQL_ERROR" >&2; exit 1; fi
        jq -nc --arg t "$STUB_BASE_CHANGED" '{data: {repository: {pullRequest: {baseRefName: $ENV.STUB_BASE,
            timelineItems: {nodes: (if $t == "" then [] else [{createdAt: $t}] end)}}}}}' | jq -r "$jq_expr" ;;
    "api repos/{owner}/{repo}/actions/runs/"*)
        jq -e --argjson id "${sub##*/}" '.[] | select(.databaseId == $id)
            | {pull_requests: (.pullRequests // [{number: ($ENV.STUB_PR | tonumber), base: {ref: "main"}}])}' "$frame" \
            | jq -r "$jq_expr" ;;
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
cat >"$root/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$STUB_DIR/calls.log"
[ "$1" = fetch ] || { echo "git stub: unexpected command: $*" >&2; exit 1; }
[ -z "${STUB_FETCH_ERROR:-}" ] || { echo "$STUB_FETCH_ERROR" >&2; exit 128; }
STUB
# The landing check's shebang resolves python3 through PATH, so this stands in for the check.
cat >"$root/bin/python3" <<'STUB'
#!/usr/bin/env bash
shift
printf 'landing-check %s body=%s\n' "$*" "$(cat "${*: -1}")" >>"$STUB_DIR/calls.log"
[ -z "${STUB_LANDING_OUT:-}" ] || echo "$STUB_LANDING_OUT"
exit "${STUB_LANDING_STATUS:-0}"
STUB
chmod +x "$root/bin/next-frame" "$root/bin/gh" "$root/bin/sleep" "$root/bin/git" "$root/bin/python3"

workflow_run() {
    local workflow=$1 id=$2 status=$3 conclusion=$4
    shift 4
    jq -nc --arg w "$workflow" --argjson id "$id" --arg s "$status" --arg c "$conclusion" \
        '{databaseId: $id, workflowName: $w, event: "pull_request", status: $s, conclusion: $c, createdAt: "2026-10-12T10:00:00Z",
          jobs: [$ARGS.positional | to_entries[] | {id: ($id * 100 + .key), name: .value, conclusion: $c}]}' --args "$@"
}

ci() { workflow_run CI "$1" "$2" "$3" swift-tests lint visual-tests; }

on_pushed() { jq -c --arg s "$pushed" '.headSha = $s' <<<"$1"; }

after_base_change() { jq -c '.createdAt = "2026-10-12T11:00:04Z"' <<<"$1"; }

from_probe_pr() { jq -c --arg b "$1" '.pullRequests = [{number: 875, base: {ref: $b}}]' <<<"$2"; }

check() {
    local name=$1 want_status=$2 want_out=$3 arg=$4
    shift 4
    local dir="$root/case" i=0 h
    rm -rf "$dir"
    mkdir -p "$dir/frames"
    for f in "$@"; do printf '%s\n' "$f" >"$dir/frames/$i.json"; i=$((i + 1)); done
    i=0
    for h in ${branch_tips:-}; do echo "$h" >"$dir/head.$i"; i=$((i + 1)); done
    echo 0 >"$dir/cursor"
    : >"$dir/calls.log"
    STUB_DIR="$dir" STUB_SHA="$sha" STUB_FORK="${fork:-}" STUB_PR_ERROR="${pr_error:-}" STUB_BASE_CHANGED="${base_changed:-}" STUB_BASE="${base:-main}" STUB_PR="${arg:-0}" STUB_GRAPHQL_ERROR="${graphql_error:-}" STUB_LANDING_STATUS="${landing_status:-0}" STUB_LANDING_OUT="${landing_out:-}" STUB_FETCH_ERROR="${fetch_error:-}" PATH="$root/bin:$PATH" "$ci_wait" ${arg:+"$arg"} >"$dir/out" 2>"$dir/err"
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

