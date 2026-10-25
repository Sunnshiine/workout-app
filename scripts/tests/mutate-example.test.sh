#!/bin/bash
set -uo pipefail

# The hand-written mutant example in AGENTS.md and mutate.sh --help addresses a line by number.
# When the source drifts the example would fail with "changed nothing", so each must still apply.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
pass=0
fail=0
examples=$(grep -hoE "scripts/mutate.sh --filter [A-Za-z]+ [^ ]+ '[^']+'" "$root/AGENTS.md" "$root/scripts/mutate-usage.sh")
[ -n "$examples" ] || { echo "FAIL: no hand-written mutant example found"; exit 1; }
while read -r _ _ suite file expr; do
    expr=${expr#\'}
    expr=${expr%\'}
    if [ ! -f "$root/$file" ]; then
        echo "FAIL: $file in the example is not a file"; fail=$((fail + 1))
    elif sed -e "$expr" "$root/$file" | cmp -s - "$root/$file"; then
        echo "FAIL: '$expr' changes nothing in $file; update the example in AGENTS.md and scripts/mutate-usage.sh"; fail=$((fail + 1))
    elif [ -z "$(find "$root/Tests" -name "$suite.swift")" ]; then
        echo "FAIL: $suite in the example names no Tests/**/$suite.swift"; fail=$((fail + 1))
    else
        echo "ok: $suite $file '$expr'"; pass=$((pass + 1))
    fi
done <<<"$examples"
printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
