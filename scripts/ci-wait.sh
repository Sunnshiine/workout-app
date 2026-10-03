#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-wait.sh [PR_NUMBER | BRANCH]

Waits for every workflow run on the head commit of a pull request (its pull_request runs) or a
branch (its push runs; default: main), then prints each workflow's conclusion and its jobs.
Exits 0 when every workflow succeeded, 1 when one failed or was cancelled, and 3 when no workflow
ran within 5 minutes.

Runs are matched by commit, so right after a merge this waits for the merge's own runs instead of
reporting the previous ones. Each workflow answers with its newest run on the commit, so a
duplicate that a newer run cancelled does not count, and a newer run that starts while this waits
is followed. A skipped run ran nothing and is left out. Only main gets push runs, so name a pull
request by its number, not its branch.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

target="${1:-main}"
if [[ "$target" =~ ^[0-9]+$ ]]; then
    sha=$(gh pr view "$target" --json headRefOid --jq .headRefOid)
    event=pull_request
else
    sha=$(gh api "repos/{owner}/{repo}/commits/$target" --jq .sha)
    # main's head also carries every issues-event agent run, enough to push its own runs past
    # any list limit.
    event=push
fi

# One line per workflow: id, status, conclusion, name. Two runs on one commit can share a
# createdAt second and list in either order, so the higher id is the newer run.
newest_runs() {
    gh run list --commit "$sha" --event "$event" --limit 100 \
        --json databaseId,workflowName,status,conclusion \
        --jq 'group_by(.workflowName) | map(max_by(.databaseId) | select(.conclusion != "skipped"))
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
    gh run watch "$pending" --interval 30 >/dev/null 2>&1 || true
    runs=$(newest_runs)
done

if [[ -z "$runs" ]]; then
    echo "no workflow ran on ${sha:0:7} within 5 minutes; path filters skipped every workflow" >&2
    exit 3
fi

failed=0
while IFS=$'\t' read -r run _ conclusion workflow; do
    echo "$workflow $conclusion on ${sha:0:7} (run $run)"
    gh run view "$run" --json jobs --jq '.jobs[] | "  \(.name): \(.conclusion)"' </dev/null
    [[ "$conclusion" == success ]] || failed=1
done <<<"$runs"
exit "$failed"
