#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-wait.sh [PR_NUMBER | PR_BRANCH | main | COMMIT]

Waits for every workflow run on the head commit of a pull request (its pull_request runs) or on
main or a commit of main (its push runs; default: main), then prints each workflow's conclusion
and its jobs. Exits 0 when every workflow succeeded, 1 when one failed or was cancelled, and 3
when no workflow ran.

Runs are matched by commit, so right after a merge this waits for the merge's own runs instead of
reporting the previous ones. Each workflow answers with its newest run on the commit that was not
skipped, passing over a run GitHub cancelled for concurrency. On a pull request such a run is
passed over only when a newer run of its workflow exists on the commit, because a push that moves
the head cancels the old head's runs too. A workflow whose runs were all passed over prints as
superseded and passes.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

target="${1:-main}"
if pr=$(gh pr view "$target" --json headRefOid --jq .headRefOid 2>&1); then
    sha=$pr
    event=pull_request
elif [[ "$pr" == *"no pull requests found for branch"* || "$pr" == *"Could not resolve to a PullRequest"* ]]; then
    sha=$(gh api "repos/{owner}/{repo}/commits/$target" --jq .sha)
    event=push
else
    echo "$pr" >&2
    exit 1
fi

concurrency_cancelled() {
    local jobs job
    jobs=$(gh api "repos/{owner}/{repo}/actions/runs/$1/jobs" --jq '.jobs[].id') || return 1
    [[ -z "$jobs" ]] && return 0
    for job in $jobs; do
        [[ $(gh api "repos/{owner}/{repo}/check-runs/$job/annotations" \
            --jq 'any(.[]; .message | startswith("Canceling since a higher priority waiting request"))') == true ]] &&
            return 0
    done
    return 1
}

newest_runs() {
    local list workflow runs record run status newer conclusion passed
    list=$(gh run list --commit "$sha" --event "$event" --limit 100 \
        --json databaseId,workflowName,status,conclusion \
        --jq 'group_by(.workflowName)[] | sort_by(-.databaseId) | .[0].databaseId as $newest
            | [.[0].workflowName, (map(select(.conclusion != "skipped")
                | "\(.databaseId):\(.status):\(.databaseId < $newest):\(.conclusion)") | join(" "))]
            | select(.[1] != "") | @tsv') || return
    while IFS=$'\t' read -r workflow runs; do
        [[ -n "$workflow" ]] || continue
        passed=""
        for record in $runs; do
            IFS=: read -r run status newer conclusion <<<"$record"
            if [[ "$conclusion" == cancelled && ("$event" == push || "$newer" == true) ]] &&
                concurrency_cancelled "$run"; then
                passed=${passed:-$run}
                continue
            fi
            printf '%s\t%s\t%s\t%s\n' "$run" "$status" "$conclusion" "$workflow"
            continue 2
        done
        printf '%s\tcompleted\tsuperseded\t%s\n' "$passed" "$workflow"
    done <<<"$list"
}

# A commit pushed seconds ago has no run yet.
runs=""
for _ in $(seq 60); do
    runs=$(newest_runs)
    [[ -n "$runs" ]] && break
    sleep 5
done

while pending=$(awk -F'\t' 'NF && $2 != "completed" { print $1; exit }' <<<"$runs"); [[ -n "$pending" ]]; do
    gh run watch "$pending" --interval 30 >/dev/null 2>&1 || sleep 30
    runs=$(newest_runs)
done

if [[ -z "$runs" ]]; then
    echo "no $event workflow ran on ${sha:0:7} within 5 minutes" >&2
    exit 3
fi

failed=0
while IFS=$'\t' read -r run _ conclusion workflow; do
    echo "$workflow $conclusion on ${sha:0:7} (run $run)"
    gh run view "$run" --json jobs --jq '.jobs[] | "  \(.name): \(.conclusion)"'
    [[ "$conclusion" == success || "$conclusion" == superseded ]] || failed=1
done <<<"$runs"
exit "$failed"
