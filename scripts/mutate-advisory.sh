#!/bin/bash
set -uo pipefail

usage() {
    cat <<'USAGE'
scripts/mutate-advisory.sh [--comment PR [--at SHA]] BASE

Runs scripts/mutate.sh --diff BASE Sources on the full swift test suite and prints the mutants
that survived as a Markdown comment body. It prints nothing when every mutant was killed, when no
mutant was generated, or when the run gave no verdict (a red baseline, busy scratch trees). A diff
that changes no Sources/ file is out of reach of swift test, and the script says so on stderr.

  --comment PR  posts the body as a comment on pull request PR of $GITHUB_REPOSITORY instead of
                printing it, or updates the comment an earlier run posted.
  --at SHA      the commit the comment names (default HEAD).

Exits 0 even when a mutant survives, because a survivor can be an equivalent mutant that no test
could kill. The mutate.sh output goes to stderr.
USAGE
}

pr="" at=""
while [ $# -gt 1 ]; do
    case $1 in
        --comment) pr=$2; shift 2 ;;
        --at) at=$2; shift 2 ;;
        *) break ;;
    esac
done
[ $# = 1 ] && [ "${1#-}" = "$1" ] || { usage >&2; exit 2; }
base=$1
script_dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

survivors() {
    if git diff --quiet "$base" HEAD -- Sources; then
        echo "mutate-advisory: this diff changes no Sources/ file, so it is out of reach of swift test" >&2
        return
    fi
    local out=$tmp/mutate.out status=0
    "$script_dir/mutate.sh" --max "${MUTATE_ADVISORY_MAX:-20}" --diff "$base" Sources >"$out" 2>&1 || status=$?
    cat "$out" >&2
    case $status in
        0 | 1) ;;
        *) echo "mutate-advisory: mutate.sh exited $status with no verdict, so nothing is posted" >&2; return ;;
    esac
    grep -q '^SURVIVED ' "$out" || return
    cat <<BODY
**Mutants that survive on the lines this fix changed** (advisory, from \`scripts/mutate.sh --diff\`)

Each row is a one-line change to the code that every \`swift test\` test still passes. Pin the
behaviour with a test, or say in the PR why the mutant is equivalent.

\`\`\`text
$(grep -E '^(SURVIVED|not run) ' "$out")
$(tail -1 "$out")
\`\`\`
BODY
}

survivors >"$tmp/survivors.md"
if [ -z "$pr" ]; then
    cat "$tmp/survivors.md"
    exit 0
fi

at=${at:-$(git rev-parse HEAD)}
marker='<!-- mutate-advisory -->'
comments="repos/$GITHUB_REPOSITORY/issues"
id=$(gh api "$comments/$pr/comments" --paginate \
    --jq ".[] | select(.body | startswith(\"$marker\")) | .id" | tail -1)
if [ -s "$tmp/survivors.md" ]; then
    { echo "$marker"; cat "$tmp/survivors.md"; echo; echo "At ${at:0:8}."; } >"$tmp/body.md"
elif [ -n "$id" ]; then
    { echo "$marker"; echo "No mutant of the changed Sources lines survives at ${at:0:8}."; } >"$tmp/body.md"
else
    exit 0
fi
if [ -n "$id" ]; then
    gh api -X PATCH "$comments/comments/$id" -F body=@"$tmp/body.md" >/dev/null
else
    gh api -X POST "$comments/$pr/comments" -F body=@"$tmp/body.md" >/dev/null
fi
