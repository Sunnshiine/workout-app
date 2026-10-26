#!/usr/bin/env bash
set -uo pipefail

usage() {
    cat <<'EOF'
scripts/receipt.sh NAME -- COMMAND [ARG ...]

Runs COMMAND in the current checkout, passes its output through with stderr merged into stdout,
then prints a receipt and appends it to the receipt file. Paste receipts into the PR body as they
are; scripts/check-receipts.py checks them in CI. A receipt is a fenced block:

    ```receipt
    name: unit
    command: swift test
    sha: <the full SHA of HEAD>
    dirty: no
    exit: 0
    summary: <the output's last non-blank line>
    ```

dirty is yes when git status shows a change or an untracked file before the run, or when the run
changed git status or HEAD, so no commit holds the tree it tested. swift test, scripts/test-sim.sh,
and the script tests end on a line that counts their tests, so the summary carries the count. The
check does not read the summary. It fails a receipt whose exit is not 0, so a red run from before a
fix belongs in prose.

The receipt file is RECEIPT_FILE, or receipts.md in this worktree's git directory, which git
status never shows.

Exits with COMMAND's status, or 2 on bad arguments or outside a git checkout.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac
if [ "$#" -lt 3 ] || [ "$2" != -- ]; then
    usage >&2
    exit 2
fi
name=$1
shift 2
if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "receipt.sh: NAME must be letters, digits, dot, dash, or underscore, got: $name" >&2
    exit 2
fi

sha=$(git rev-parse --verify HEAD 2>/dev/null) || {
    echo "receipt.sh: run it inside a git checkout with a commit" >&2
    exit 2
}
before=$(git status --porcelain)
dirty=no
[ -z "$before" ] || dirty=yes
file=${RECEIPT_FILE:-$(git rev-parse --path-format=absolute --git-path receipts.md)}

log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
[ "$(git status --porcelain)" = "$before" ] && [ "$(git rev-parse --verify HEAD 2>/dev/null)" = "$sha" ] || dirty=yes

summary=$(sed -e $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' -e $'s/\r$//' "$log" | awk 'NF { line = $0 } END { print line }' | tr '`' "'")

receipt=$(
    echo '```receipt'
    echo "name: $name"
    echo "command: $(printf '%q ' "$@" | sed 's/ $//')"
    echo "sha: $sha"
    echo "dirty: $dirty"
    echo "exit: $status"
    echo "summary: $summary"
    echo '```'
)
printf '\n%s\n' "$receipt"
printf '%s\n\n' "$receipt" >>"$file"
echo "receipt.sh: appended to $file" >&2
exit "$status"
