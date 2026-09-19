#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/mutate.sh --filter SUITE FILE SED_EXPR [SED_EXPR...]

Checks that a pin catches the changes it claims to. Runs `swift test --filter SUITE` once on
the untouched FILE, which must pass, then once per SED_EXPR applied to FILE, and prints the
tests each mutant fails. A mutant no test fails SURVIVED: the pin does not cover that change.

  SED_EXPR  one sed command carrying its own address, such as '67s/failed: /exploded: /'
            or '84s|.*|// mutant|'. An expression that leaves FILE unchanged is an error,
            because it would otherwise read as a survivor.

Exits 0 when every mutant was killed, 1 when any survived or did not compile, 2 on a usage
or setup error. FILE is restored after each mutant and on exit, uncommitted edits included.
EOF
}

filter=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)
            filter="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) break ;;
    esac
done
if [[ -z "$filter" || $# -lt 2 ]]; then
    usage >&2
    exit 2
fi

file="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
shift
cd "$(git rev-parse --show-toplevel)"

original=$(mktemp)
cp "$file" "$original"
trap 'cp "$original" "$file"; rm -f "$original"' EXIT

indent() { sed 's/^/  /'; }

# Prints the failing tests one per line, or one line starting with "!" when the suite never ran.
failing_tests() {
    local out count
    out=$(swift test --filter "$filter" 2>&1) || true
    count=$(sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p' <<<"$out" | tail -1)
    if [[ "$count" == 0 ]] || grep -q 'No matching test cases were run' <<<"$out"; then
        echo "! --filter $filter matched no tests"
    elif [[ -z "$count" ]]; then
        echo "! did not compile"
    else
        grep -v 'Test run with' <<<"$out" | sed -nE 's/^[^[:alpha:]]*Test (.+) failed after .*/\1/p' | sort -u
    fi
}

baseline=$(failing_tests)
if [[ -n "$baseline" ]]; then
    echo "the suite must pass before mutating; untouched it reports:" >&2
    indent <<<"$baseline" >&2
    exit 2
fi

status=0
for expr in "$@"; do
    sed "$expr" "$original" >"$file"
    if cmp -s "$file" "$original"; then
        echo "'$expr' changed nothing in $(basename "$file"); check its address" >&2
        exit 2
    fi
    echo "--- $expr"
    result=$(failing_tests)
    if [[ -z "$result" ]]; then
        echo "  SURVIVED"
        status=1
    else
        indent <<<"$result"
        if [[ "$result" == "!"* ]]; then
            status=1
        fi
    fi
    cp "$original" "$file"
done
exit "$status"
