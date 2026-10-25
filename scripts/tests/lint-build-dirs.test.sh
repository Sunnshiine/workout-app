#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}

fixture() {
    rm -rf "$root/fx"
    mkdir -p "$root/fx/scripts/tests" "$root/fx/.agents/skills/verify"
    cp "$script_dir/../lint-build-dirs.sh" "$root/fx/scripts/"
    printf 'results_dirs=(%s)\nregenerable_dirs=(%s)\n' "$1" "$2" >"$root/fx/scripts/build-dirs.sh"
    printf 'mkdir -p .build/runs\n' >"$root/fx/scripts/run.sh"
    printf 'rm -rf .build/scratch\n' >"$root/fx/scripts/clean.sh"
    printf 'out = ".build/shots"\n' >"$root/fx/.agents/skills/verify/shot.py"
    printf 'ls .build/fixture-only\n' >"$root/fx/scripts/tests/run.test.sh"
}
lint() { out=$("$root/fx/scripts/lint-build-dirs.sh" 2>&1); echo "$? $out"; }

expect "this checkout's scripts name only the .build dirs scripts/build-dirs.sh lists" \
    "$("$script_dir/../lint-build-dirs.sh" >/dev/null 2>&1; echo "exit $?")" "exit 0"

fixture "runs shots" "scratch"
expect "a dir in either list passes, and a test's .build dir is not a script's" "$(lint)" "0 ==> Clean: 3 .build dirs scripts name, each in one list"

fixture "runs" "scratch"
printf 'mkdir -p .build/new\n' >>"$root/fx/scripts/run.sh"
expect "a .build dir in neither list fails, naming where a script names it and the file to add it to" "$(lint)" \
    "1 .agents/skills/verify/shot.py:1 names .build/shots, which scripts/build-dirs.sh lists in neither results_dirs (lane.sh down saves it) nor regenerable_dirs (down drops it); add it to one
scripts/run.sh:2 names .build/new, which scripts/build-dirs.sh lists in neither results_dirs (lane.sh down saves it) nor regenerable_dirs (down drops it); add it to one"

fixture "runs shots gone" "scratch"
expect "a listed dir no script names fails, so a list cannot outlive the script" "$(lint)" \
    "1 scripts/build-dirs.sh lists gone, which no script names as .build/gone; remove it"

fixture "runs shots scratch" "scratch"
expect "a dir in both lists fails" "$(lint)" \
    "1 scripts/build-dirs.sh lists scratch in both results_dirs and regenerable_dirs; keep one"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
