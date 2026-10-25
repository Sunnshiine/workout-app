#!/bin/bash
set -uo pipefail

usage() {
    cat <<'EOF'
scripts/mutate-advisory.sh BASE

Runs scripts/mutate.sh --diff BASE Sources on the full swift test suite and prints the mutants
that survived as a Markdown comment body. CI posts that body on a fix pull request. It prints
nothing when every mutant was killed, when no mutant was generated, or when the run gave no
verdict (a red baseline, busy scratch trees). A diff that changes no Sources/ file is out of
reach of swift test, and the script says so on stderr.

Always exits 0, because a surviving mutant can be an equivalent one that no test could kill. The
mutate.sh output goes to stderr.
EOF
}

[ $# = 1 ] && [ "${1#-}" = "$1" ] || { usage >&2; exit 2; }
base=$1
script_dir=$(cd "$(dirname "$0")" && pwd)

if git diff --quiet "$base" HEAD -- Sources; then
    echo "mutate-advisory: this diff changes no Sources/ file, so it is out of reach of swift test" >&2
    exit 0
fi

out=$(mktemp)
trap 'rm -f "$out"' EXIT
status=0
"$script_dir/mutate.sh" --max "${MUTATE_ADVISORY_MAX:-20}" --diff "$base" Sources >"$out" 2>&1 || status=$?
cat "$out" >&2
case $status in
    0 | 1) ;;
    *) echo "mutate-advisory: mutate.sh exited $status with no verdict, so nothing is posted" >&2; exit 0 ;;
esac
grep -q '^SURVIVED ' "$out" || exit 0

cat <<EOF
**Mutants that survive on the lines this fix changed** (advisory, from \`scripts/mutate.sh --diff\`)

Each row is a one-line change to the code that every \`swift test\` test still passes. Pin the
behaviour with a test, or say in the PR why the mutant is equivalent.

\`\`\`text
$(grep -E '^(SURVIVED|not run) ' "$out")
$(tail -1 "$out")
\`\`\`
EOF
exit 0
