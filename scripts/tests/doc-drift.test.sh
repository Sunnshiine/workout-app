#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

lines() {
    for i in $(seq 1 20); do printf 'echo "%s scenario number %02d checks one thing"\n' "$1" "$i"; done
}

repo="$tmp/repo"
mkdir -p "$repo/scripts/tests" "$repo/docs/guide" "$repo/tools"
cp "$script_dir/../doc-drift.py" "$script_dir/../lint-doc-symbols.py" "$repo/scripts/"
cd "$repo" || exit 3
git init -q -b main
git config user.email test@example.com
git config user.name test
lines admission >scripts/tests/admission.test.sh
lines lane >scripts/lane.sh
lines guide >docs/guide/README.md
printf '# Tools\n' >tools/README.md
lines tiny | head -n 10 >scripts/tests/tiny.test.sh
lines partial >scripts/tests/partial.test.sh
printf 'Run `scripts/tests/admission.test.sh` after an edit to the lock.\n' >AGENTS.md
printf 'Also run `scripts/tests/tiny.test.sh` and `scripts/tests/partial.test.sh`.\n' >>AGENTS.md
printf 'Make a lane with `scripts/lane.sh up`. Each folder has a `README.md`.\n' >docs/TESTING.md
printf 'The steps are in [README.md](README.md).\n' >docs/guide/index.md
git add -A && git commit -qm base
git switch -q -c split

head -n 10 scripts/tests/admission.test.sh >scripts/tests/admission-claim.test.sh
tail -n 10 scripts/tests/admission.test.sh >scripts/tests/admission-slots.test.sh
printf 'echo "admission entry"\n' >scripts/tests/admission.test.sh
printf '. "$(dirname "$0")/lane-help.sh"\n' >scripts/lane.sh
lines lane >scripts/lane-help.sh
cp scripts/tests/tiny.test.sh scripts/tests/tiny-copy.test.sh
printf 'echo "tiny entry"\n' >scripts/tests/tiny.test.sh
head -n 4 scripts/tests/partial.test.sh >scripts/tests/partial-kept.test.sh
lines rewritten >scripts/tests/partial.test.sh
mv docs/guide/README.md docs/guide/steps.md
printf '# Guide\n' >docs/guide/README.md
printf 'The admission parts are `admission-claim.test.sh` and `scripts/tests/admission.test.sh`.\n' >docs/parts.md
git add -A && git commit -qm split

out=$(python3 scripts/doc-drift.py main)
status=$?
[ "$status" -eq 0 ] && ok "a listing exits 0" || bad "a listing exits 0, got $status"
printf '%s\n' "$out" | grep -Fq 'scripts/tests/admission.test.sh moved lines into scripts/tests/admission-claim.test.sh, scripts/tests/admission-slots.test.sh.' \
    && ok "a test split in parts names every part" || bad "a test split in parts names every part: $out"
printf '%s\n' "$out" | grep -Fxq '  AGENTS.md:1: Run `scripts/tests/admission.test.sh` after an edit to the lock.' \
    && ok "a doc naming the split test is listed" || bad "a doc naming the split test is listed: $out"
printf '%s\n' "$out" | grep -q 'scripts/lane.sh moved' \
    && bad "a script whose lines went into a helper it sources is listed: $out" \
    || ok "a script whose lines went into a helper it sources is not listed"
printf '%s\n' "$out" | grep -Fxq '  docs/guide/index.md:1: The steps are in [README.md](README.md).' \
    && ok "a sibling doc naming the moved file by its bare name is listed" \
    || bad "a sibling doc naming the moved file by its bare name is listed: $out"
printf '%s\n' "$out" | grep -q 'docs/TESTING.md' \
    && bad "a bare name that several tracked files share is listed: $out" \
    || ok "a bare name that several tracked files share is not listed"
printf '%s\n' "$out" | grep -q 'docs/parts.md' \
    && bad "a doc line the branch added is listed: $out" \
    || ok "a doc line the branch added is not listed"

printf '%s\n' "$out" | grep -q 'tiny.test.sh moved' \
    && bad "a file that lost fewer than 15 long lines is listed: $out" \
    || ok "a file that lost fewer than 15 long lines is not listed"
printf '%s\n' "$out" | grep -q 'partial.test.sh moved' \
    && bad "a file where under half the lost lines landed elsewhere is listed: $out" \
    || ok "a file where under half the lost lines landed elsewhere is not listed"

out=$(python3 scripts/doc-drift.py HEAD)
[ -z "$out" ] && ok "a branch with no moves prints nothing" || bad "a branch with no moves prints nothing: $out"

python3 scripts/doc-drift.py no-such-ref 2>/dev/null
status=$?
[ "$status" -eq 2 ] && ok "a ref that does not resolve exits 2" || bad "a ref that does not resolve exits 2, got $status"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
