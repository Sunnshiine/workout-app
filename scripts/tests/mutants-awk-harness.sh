# shellcheck shell=bash
# Sourced by the mutants-awk tests: a temp dir, ok/bad counters, and check, which runs the
# generator on $tmp/F.swift and compares its rows.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scan="$script_dir/../mutants-scan.awk"
generator="$script_dir/../mutants.awk"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

check() {
    local name=$1 got want n mutated
    shift
    if [ $# -eq 0 ]; then
        awk '{ print NR }' "$tmp/F.swift" >"$tmp/changed"
    else
        printf '%s\n' "$@" >"$tmp/changed"
    fi
    want=$(cat)
    : >"$tmp/compiled-out"
    awk -v path=Sources/F.swift -v changed="$tmp/changed" -v platform="${PLATFORM:-}" -v compiledOut="$tmp/compiled-out" \
        -f "$scan" -f "$generator" "$tmp/F.swift" >"$tmp/rows"
    got=$(awk 'BEGIN { FS = "\t"; OFS = " | " } { $1 = $1; print (FILENAME ~ /compiled-out$/ ? "compiled out: " : "") $0 }' \
        "$tmp/rows" "$tmp/compiled-out")
    if [ "$got" = "$want" ]; then
        ok "$name"
    else
        bad "$name"
        diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/       /'
    fi
    while IFS=$'\t' read -r _ n _ _ _ mutated; do
        MUTATED=$mutated awk -v n="$n" 'NR == n { print ENVIRON["MUTATED"]; next } { print }' \
            "$tmp/F.swift" >"$tmp/mutant.swift"
        if [ "$(diff "$tmp/F.swift" "$tmp/mutant.swift" | grep -v '^[<>-]')" = "${n}c${n}" ]; then
            ok "$name: mutant on line $n changes only line $n"
        else
            bad "$name: mutant on line $n changes only line $n"
        fi
    done <"$tmp/rows"
}
