#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-wait.sh PR_NUMBER

Waits for every pull_request workflow run on the tip of the pull request's branch, then prints
each workflow's conclusion and its jobs. Each workflow answers with its newest run that was not
skipped. When every workflow succeeded, prints the gh pr merge command pinned to that commit.

A run counts only when it tested the PR's current base. The PR's own run counts when it was created
after the PR's latest base change, since retargeting a stacked PR, by hand or when its parent
merges, leaves the head alone. Another PR's run on the same commit, such as a probe PR's, counts
when that PR has the same base.

Before it prints the merge command, it fetches the base and runs scripts/landing-reverts-main.py,
which refuses a landing that undoes a recent commit on the base unless the PR body says
`Reverts #N`, or `Reverts <sha>` for a commit with no PR number.

Exits 0 when every workflow succeeded; 1 when one did not, a run tested another base, the head moved during the wait, the PR comes from a fork, a gh or git call failed, or the landing would undo a commit on the base; 2 on a missing or
non-numeric argument; and 3 when no workflow ran.
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
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
branch=$(gh pr view "$pr" --json headRefName,isCrossRepository --jq 'select(.isCrossRepository | not) | .headRefName')
[[ -n "$branch" ]] || { echo "#$pr comes from a fork, and ci-wait.sh does not handle fork PRs" >&2; exit 1; }
# headRefOid lags a push by up to two minutes (#694); the branch ref moves at push time.
head_sha() { gh api "repos/{owner}/{repo}/git/ref/heads/$branch" --jq .object.sha; }
sha=$(head_sha) || { echo "branch $branch of #$pr is gone" >&2; exit 1; }

newest_runs() {
    gh run list --commit "$sha" --event pull_request --limit 100 \
        --json databaseId,workflowName,status,conclusion,createdAt \
        --jq 'map(select(.conclusion != "skipped")) | group_by(.workflowName)[] | max_by(.databaseId)
            | [.databaseId, .status, .conclusion, .createdAt, .workflowName] | @tsv'
}

base_and_last_change() {
    gh api graphql -F owner='{owner}' -F repo='{repo}' -F pr="$pr" -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              baseRefName
              timelineItems(itemTypes: [BASE_REF_CHANGED_EVENT, AUTOMATIC_BASE_CHANGE_SUCCEEDED_EVENT], last: 1) {
                nodes {
                  ... on BaseRefChangedEvent { createdAt }
                  ... on AutomaticBaseChangeSucceededEvent { createdAt }
                }
              }
            }
          }
        }' --jq '.data.repository.pullRequest | [.baseRefName, (.timelineItems.nodes[0].createdAt // "")] | @tsv'
}

prs_and_bases_of_run() {
    gh api "repos/{owner}/{repo}/actions/runs/$1" --jq '.pull_requests[] | [.number, .base.ref] | @tsv'
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

base_info=$(base_and_last_change)
IFS=$'\t' read -r base base_changed <<<"$base_info"
failed=0
stale=0
while IFS=$'\t' read -r run _ conclusion created workflow; do
    # GitHub fills a run's pull_requests[].base at query time, so the PR's own run needs the time check.
    prs_and_bases=$(prs_and_bases_of_run "$run")
    tested=""
    while IFS=$'\t' read -r number ref; do
        [[ "$ref" == "$base" ]] || continue
        [[ "$number" == "$pr" && "$created" < "$base_changed" ]] || tested=1
    done <<<"$prs_and_bases"
    if [[ -z "$tested" ]]; then
        echo "$workflow ran on ${sha:0:7} against a base other than #$pr's $base (run $run)"
        stale=1
        continue
    fi
    echo "$workflow $conclusion on ${sha:0:7} (run $run)"
    gh run view "$run" --json jobs --jq '.jobs[] | "  \(.name): \(.conclusion)"'
    [[ "$conclusion" == success ]] || failed=1
done <<<"$runs"
[[ "$stale" == 0 ]] || echo "push to $branch, an empty commit if nothing changed, so every workflow runs against $base" >&2
[[ "$failed" == 0 && "$stale" == 0 ]] || exit 1

body=$(mktemp)
trap 'rm -f "$body"' EXIT
gh pr view "$pr" --json body --jq .body >"$body" || exit 1
git fetch -q --no-tags origin "+refs/heads/$base:refs/remotes/origin/$base" "$sha" \
    || { echo "could not fetch $base and ${sha:0:7} for the landing check" >&2; exit 1; }
if ! "$script_dir/landing-reverts-main.py" "origin/$base" "$sha" --body-file "$body"; then
    echo "the landing of #$pr onto $base fails scripts/landing-reverts-main.py, so there is no merge command" >&2
    exit 1
fi
echo "gh pr merge $pr --squash --match-head-commit $sha"
