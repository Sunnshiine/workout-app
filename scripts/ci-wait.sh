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
skipped. A run cancelled by a newer run of its workflow does not count: on the same commit the
newer run answers instead, and on main a later commit's run supersedes it.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

target="${1:-main}"
if sha=$(gh pr view "$target" --json headRefOid --jq .headRefOid 2>/dev/null); then
    event=pull_request
else
    sha=$(gh api "repos/{owner}/{repo}/commits/$target" --jq .sha)
    # main's head also carries every issues-event agent run, enough to push its own runs past
    # any list limit.
    event=push
fi

newest_runs() {
    gh run list --commit "$sha" --event "$event" --limit 100 \
        --json databaseId,workflowName,status,conclusion \
        --jq 'group_by(.workflowName) | map(
                (map(select(.conclusion != "skipped")) | max_by(.databaseId)) as $ran
                | select($ran != null and ($ran.conclusion != "cancelled" or $ran == max_by(.databaseId)))
                | $ran)
            | .[] | [.databaseId, .status, .conclusion, .workflowName] | @tsv'
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
    echo "no workflow ran on ${sha:0:7}; path filters or job conditions skipped every one" >&2
    exit 3
fi

failed=0
while IFS=$'\t' read -r run _ conclusion workflow; do
    if [[ "$event" == push && "$conclusion" == cancelled ]] &&
        (( $(gh run list --workflow "$workflow" --event push --limit 1 --json databaseId --jq '.[0].databaseId' </dev/null) > run )); then
        conclusion=superseded
    fi
    echo "$workflow $conclusion on ${sha:0:7} (run $run)"
    gh run view "$run" --json jobs --jq '.jobs[] | "  \(.name): \(.conclusion)"' </dev/null
    [[ "$conclusion" == success || "$conclusion" == superseded ]] || failed=1
done <<<"$runs"
exit "$failed"
