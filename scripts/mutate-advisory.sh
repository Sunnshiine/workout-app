#!/bin/bash
set -uo pipefail

usage() {
    cat <<'USAGE'
scripts/mutate-advisory.sh [--comment PR [--at SHA]] BASE

Runs scripts/mutate.sh --diff BASE Sources on the full swift test suite and prints a Markdown
comment body that names one of these outcomes:
  survived    the mutants that every test still passes, with any --max left out
  killed      every generated mutant ran and a test killed it
  partial     none survived, but some did not compile, errored, were flaky, or were left out
  none        no mutant was generated on the changed lines
  no verdict  mutate.sh exited 2 (a red baseline) or 75 (busy scratch trees), so none ran
  no Sources  the diff changes no Sources/ file, which is out of reach of swift test

  --comment PR  posts the body on pull request PR of $GITHUB_REPOSITORY instead of printing it.
                Only survivors post a new comment. Every outcome updates the comment an earlier
                run of github-actions[bot] posted, so it never keeps a stale verdict.
  --at SHA      the commit the comment names (default HEAD).

Exits 0 even when a mutant survives, because a survivor can be an equivalent mutant that no test
could kill. The mutate.sh output goes to stderr, and with --comment the outcome and body follow it.
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

rows() {
    printf '\n```text\n'
    grep -E "^($1) " "$tmp/mutate.out"
    tail -1 "$tmp/mutate.out"
    printf '```\n'
}

# Prints the body and sets outcome.
report() {
    if git diff --quiet "$base" HEAD -- Sources; then
        outcome="no Sources"
        echo "This diff changes no Sources/ file, so it is out of reach of swift test and no mutant runs."
        return
    fi
    local status=0 summary
    "$script_dir/mutate.sh" --max "${MUTATE_ADVISORY_MAX:-20}" --diff "$base" Sources >"$tmp/mutate.out" 2>&1 || status=$?
    cat "$tmp/mutate.out" >&2
    summary=$(tail -1 "$tmp/mutate.out")
    if [ "$status" != 0 ] && [ "$status" != 1 ]; then
        outcome="no verdict"
        echo "mutate.sh exited $status with no verdict, so no mutant ran. The job log names the cause, such as a red baseline (2) or busy scratch trees (75)."
    elif grep -q '^SURVIVED ' "$tmp/mutate.out"; then
        outcome=survived
        echo "**Mutants that survive on the lines this fix changed** (advisory, from \`scripts/mutate.sh --diff\`)"
        echo
        echo "Each row is a one-line change to the code that every \`swift test\` test still passes. Pin the"
        echo "behaviour with a test, or say in the PR why the mutant is equivalent."
        rows 'SURVIVED|not run'
    elif [[ $summary == "mutants: 0 "* ]]; then
        outcome=none
        echo "No mutant was generated on the changed Sources lines."
    elif [ "$status" = 0 ] && [[ $summary =~ ^([0-9]+)\ mutants?:\ ([0-9]+)\ killed$ ]] &&
        [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]; then
        outcome=killed
        echo "Every mutant of the changed Sources lines was killed ($summary)."
    else
        outcome=partial
        echo "No mutant survived, but not every mutant was run and killed, so the changed lines may still be unpinned:"
        rows 'nocompile|error|flaky|unreachable|not run'
    fi
}

report >"$tmp/report.md"
if [ -z "$pr" ]; then
    cat "$tmp/report.md"
    exit 0
fi

echo "mutate-advisory: $outcome" >&2
cat "$tmp/report.md" >&2
at=${at:-$(git rev-parse HEAD)}
marker='<!-- mutate-advisory -->'
comments="repos/$GITHUB_REPOSITORY/issues"
id=$(gh api "$comments/$pr/comments" --paginate \
    --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$marker\"))) | .id" | tail -1)
{ echo "$marker"; cat "$tmp/report.md"; echo; echo "At ${at:0:8}."; } >"$tmp/body.md"
if [ -n "$id" ]; then
    gh api -X PATCH "$comments/comments/$id" -F body=@"$tmp/body.md" >/dev/null
elif [ "$outcome" = survived ]; then
    gh api -X POST "$comments/$pr/comments" -F body=@"$tmp/body.md" >/dev/null
fi
