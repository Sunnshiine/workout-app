#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-skill-links.sh"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect_exit() {
    if [ "$2" -eq "$3" ]; then ok "$1 exits $3"; else bad "$1 exits $3, got $2"; fi
}

expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1: $3"; else bad "$1 is missing the line: $3"; fi
}

expect_count() {
    local got
    got=$(printf '%s\n' "$2" | grep -c '^error: ')
    if [ "$got" -eq "$3" ]; then ok "$1 reports $3 error(s)"; else bad "$1 reports $3 error(s), got $got"; fi
}

linked_tree() {
    local root="$tmp/$1" name
    shift
    mkdir -p "$root/.agents/skills" "$root/.claude/skills"
    for name in "$@"; do
        mkdir "$root/.agents/skills/$name"
        ln -s "../../.agents/skills/$name" "$root/.claude/skills/$name"
    done
    echo "$root"
}

check() {
    out=$("$checker" "$1" 2>&1)
    status=$?
}

echo "every skill folder linked: clean"
root=$(linked_tree clean grilling verify)
check "$root"
expect_exit "clean" "$status" 0
expect_line "clean" "$out" "==> Clean: 2 skills, each linked from .claude/skills"

echo "a skill folder with no link is named, with the command that links it"
root=$(linked_tree unlinked grilling verify)
mkdir "$root/.agents/skills/grilling-frontend-prototyping"
check "$root"
expect_exit "unlinked" "$status" 1
expect_count "unlinked" "$out" 1
expect_line "unlinked" "$out" "error: .agents/skills/grilling-frontend-prototyping has no link in .claude/skills, so Claude Code cannot load it."
expect_line "unlinked" "$out" "       ln -s ../../.agents/skills/grilling-frontend-prototyping .claude/skills/grilling-frontend-prototyping"

echo "a link whose skill folder is gone is named"
root=$(linked_tree dangling grilling verify)
rm -r "$root/.agents/skills/verify"
check "$root"
expect_exit "dangling" "$status" 1
expect_count "dangling" "$out" 1
expect_line "dangling" "$out" "error: .claude/skills/verify must be a link to ../../.agents/skills/verify, an existing skill folder. It is: ../../.agents/skills/verify"

echo "a link that resolves today but by another path is named"
root=$(linked_tree absolute grilling)
rm "$root/.claude/skills/grilling"
ln -s "$root/.agents/skills/grilling" "$root/.claude/skills/grilling"
check "$root"
expect_exit "absolute" "$status" 1
expect_line "absolute" "$out" "error: .claude/skills/grilling must be a link to ../../.agents/skills/grilling, an existing skill folder. It is: $root/.agents/skills/grilling"

echo "a skill copied into .claude/skills instead of linked is named"
root=$(linked_tree copied grilling)
rm "$root/.claude/skills/grilling"
cp -R "$root/.agents/skills/grilling" "$root/.claude/skills/grilling"
check "$root"
expect_exit "copied" "$status" 1
expect_count "copied" "$out" 1
expect_line "copied" "$out" "error: .claude/skills/grilling must be a link to ../../.agents/skills/grilling, an existing skill folder. It is: not a link"

echo "every failure is reported, not only the first"
root=$(linked_tree several grilling verify)
mkdir "$root/.agents/skills/tdd" "$root/.agents/skills/triage"
ln -s ../../.agents/skills/handoff "$root/.claude/skills/handoff"
check "$root"
expect_exit "several" "$status" 1
expect_count "several" "$out" 3

echo "a tree with no skill folder is a usage error, not a clean run"
root=$(linked_tree empty)
check "$root"
expect_exit "empty" "$status" 2

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
