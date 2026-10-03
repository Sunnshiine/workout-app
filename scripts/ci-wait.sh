#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-wait.sh PR_NUMBER

Waits for every pull_request workflow run on the tip of the pull request's branch, then prints
each workflow's conclusion and its jobs. Each workflow answers with its newest run that was not
skipped. When every workflow succeeded, prints the gh pr merge command pinned to that commit.

Exits 0 when every workflow succeeded; 1 when one did not, the head moved during the wait, the PR
comes from a fork, or a gh call failed; 2 on a missing or non-numeric argument; and 3 when no
workflow ran.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    "" | *[!0-9]*)
        usage >&2
        exit 2
        ;;
esac

pr=$1
branch=$(gh pr view "$pr" --json headRefName,isCrossRepository --jq 'select(.isCrossRepository | not) | .headRefName')
[[ -n "$branch" ]] || { echo "#$pr comes from a fork, and ci-wait.sh does not handle fork PRs" >&2; exit 1; }
# headRefOid lags a push by up to two minutes (#694); the branch ref moves at push time.
head_sha() { gh api "repos/{owner}/{repo}/git/ref/heads/$branch" --jq .object.sha; }
sha=$(head_sha) || { echo "branch $branch of #$pr is gone" >&2; exit 1; }

newest_runs() {
    gh run list --commit "$sha" --event pull_request --limit 100 \
        --json databaseId,workflowName,status,conclusion \
        --jq 'map(select(.conclusion != "skipped")) | group_by(.workflowName)[] | max_by(.databaseId)
            | [.databaseId, .status, .conclusion, .workflowName] | @tsv'
}

for _ in $(seq 60); do
    runs=$(newest_runs)
    [[ -n "$runs" ]] && break
    sleep 5
done
# An earlier event's runs on this commit can all be finished before GitHub creates the new event's runs.
sleep 15
runs=$(newest_runs)
while pending=$(awk -F'\t' 'NF && $2 != "completed" { print $1; exit }' <<<"$runs"); [[ -n "$pending" ]]; do
    gh run watch "$pending" --interval 30 >/dev/null 2>&1 || sleep 30
    runs=$(newest_runs)
done

now=$(head_sha)
if [[ "$now" != "$sha" ]]; then
    echo "the head of #$pr moved from ${sha:0:7} to ${now:0:7} during the wait; run ci-wait.sh $pr again" >&2
    exit 1
fi

if [[ -z "$runs" ]]; then
    echo "no pull_request workflow ran on ${sha:0:7} within 5 minutes" >&2
    echo "land #$pr only when every path it changes is in ci.yml's paths-ignore and no agent workflow pushed ${sha:0:7} (#805)" >&2
    exit 3
fi

failed=0
while IFS=$'\t' read -r run _ conclusion workflow; do
    echo "$workflow $conclusion on ${sha:0:7} (run $run)"
    gh run view "$run" --json jobs --jq '.jobs[] | "  \(.name): \(.conclusion)"'
    [[ "$conclusion" == success ]] || failed=1
done <<<"$runs"
[[ "$failed" == 0 ]] || exit 1
echo "gh pr merge $pr --squash --match-head-commit $sha"
