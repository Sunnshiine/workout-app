#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-wait.sh [PR_NUMBER | BRANCH]

Waits for the CI workflow run on the head commit of a pull request or branch (default: main),
then prints each job's conclusion. Exits 0 only when the run succeeded.

The run is matched by commit, so right after a merge this waits for the merge's own run
instead of reporting the previous one. This reports the newest run on the commit and follows
a newer one that starts while it waits. A cancelled run with no newer run prints as cancelled.
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
else
    sha=$(gh api "repos/{owner}/{repo}/commits/$target" --jq .sha)
fi

# Two runs on one commit can share a createdAt second, and the API can then list the
# older one first.
newest_run() {
    gh run list --workflow CI --commit "$sha" --limit 20 --json databaseId --jq 'map(.databaseId) | max // empty'
}

# A commit pushed seconds ago has no run yet.
run=""
for _ in $(seq 60); do
    run=$(newest_run)
    [[ -n "$run" ]] && break
    sleep 5
done
if [[ -z "$run" ]]; then
    echo "no CI run for ${sha:0:7} after 5 minutes; ci.yml paths-ignore skips docs-only changes" >&2
    exit 3
fi

while :; do
    gh run watch "$run" --interval 30 >/dev/null 2>&1 || true
    newer=$(newest_run)
    (( newer > run )) || break
    run=$newer
done
conclusion=$(gh run view "$run" --json conclusion --jq .conclusion)
echo "CI $conclusion on ${sha:0:7} (run $run)"
gh run view "$run" --json jobs --jq '.jobs[] | "  \(.name): \(.conclusion)"'
[[ "$conclusion" == success ]]
