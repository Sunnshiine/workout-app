#!/bin/bash
set -uo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1: $3"; else bad "$1 is missing the line: $3"; printf '%s\n' "$2"; fi
}

bytes() { head -c "$2" /dev/zero | tr '\0' x >"$repo/$1"; }

commit() {
    local before after
    before=$(git -C "$repo" rev-parse -q --verify HEAD)
    out=$(git -C "$repo" commit -q "$@" -m test 2>&1)
    status=$?
    after=$(git -C "$repo" rev-parse -q --verify HEAD)
    [ "$before" != "$after" ] && moved=1 || moved=0
}

expect_commits() {
    if [ "$status" -eq 0 ] && [ "$moved" -eq 1 ]; then ok "$1 commits"; else bad "$1 commits, got exit $status"; printf '%s\n' "$out"; fi
}

expect_blocked() {
    if [ "$status" -eq 1 ] && [ "$moved" -eq 0 ]; then ok "$1 is blocked"; else bad "$1 is blocked, got exit $status moved=$moved"; fi
    git -C "$repo" reset -q
}

git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false
mkdir -p "$repo/scripts" "$repo/hooks"
cp "$src/scripts/check-token-budget.sh" "$repo/scripts/"
cp "$src/.githooks/pre-commit" "$repo/hooks/"
cp "$src/.gitattributes" "$repo/"
git -C "$repo" config core.hooksPath hooks

echo "the first commit on an unborn branch is checked"
bytes big.txt 20001
git -C "$repo" add -A
commit
expect_blocked "a 20001-byte file on an unborn branch"
rm "$repo/big.txt"
git -C "$repo" add -A
commit
expect_commits "the scripts and .gitattributes"

echo "an over-limit text file is named with the split instructions"
mkdir -p "$repo/Tests/Unit"
bytes Tests/Unit/BigTests.swift 41000
git -C "$repo" add -A
commit
expect_blocked "a 41000-byte Swift file"
expect_line "over limit" "$out" "error: these staged files are over the 5000-token limit (tokens = bytes / 4):"
expect_line "over limit" "$out" "  Tests/Unit/BigTests.swift: 10250 tokens (41000 bytes). Split it into at least 3 files."
expect_line "over limit" "$out" "How to split:"
expect_line "over limit" "$out" "- Split along responsibilities, not at a line count. Each new file holds one cohesive concern"
expect_line "over limit" "$out" "  \`extension <ExistingSuite> { ... }\` or as whole top-level @Test functions. Name the file"
expect_line "over limit" "$out" "swift test."
rm "$repo/Tests/Unit/BigTests.swift"

echo "the limit is 20000 bytes, inclusive"
bytes edge.txt 20000
git -C "$repo" add edge.txt
commit
expect_commits "a 20000-byte file"
bytes edge.txt 20001
git -C "$repo" add edge.txt
commit
expect_blocked "growing it to 20001 bytes"
expect_line "one byte over" "$out" "  edge.txt: 5001 tokens (20001 bytes). Split it into at least 2 files."

echo "machine-written and binary files are skipped"
mkdir -p "$repo/tools/crap" "$repo/App.xcodeproj" "$repo/.agents/skills/verify/tests/fixtures"
bytes package-lock.json 30000
bytes tools/crap/Package.resolved 30000
bytes App.xcodeproj/project.pbxproj 30000
bytes .agents/skills/verify/tests/fixtures/home.describe-ui.json 30000
head -c 30000 /dev/zero >"$repo/icon.png"
git -C "$repo" add package-lock.json tools App.xcodeproj .agents icon.png
commit
expect_commits "lockfiles, a pbxproj, a captured fixture, and a binary over the limit"

echo "the staged blob is measured, not the working copy"
git -C "$repo" checkout -q edge.txt
bytes small.txt 100
git -C "$repo" add small.txt
bytes small.txt 30000
commit
expect_commits "a small staged file with a big working copy"
bytes small.txt 30000
git -C "$repo" add small.txt
bytes small.txt 100
commit
expect_blocked "a big staged file with a small working copy"
git -C "$repo" checkout -q small.txt

echo "deleting an over-limit file is allowed"
bytes big.txt 30000
git -C "$repo" add big.txt
git -C "$repo" commit -q --no-verify -m "big file from before the hook"
git -C "$repo" rm -q big.txt
commit
expect_commits "removing a tracked 30000-byte text file"

echo "a path with spaces and unicode is checked and named"
bytes "Design notes é.md" 25000
git -C "$repo" add -A
commit
expect_blocked "a 25000-byte file named with a space"
expect_line "spaced path" "$out" "  Design notes é.md: 6250 tokens (25000 bytes). Split it into at least 2 files."
rm "$repo/Design notes é.md"

echo "git commit -a and git commit <path> check the index they build"
bytes small.txt 30000
commit -a
expect_blocked "commit -a with a tracked file grown past the limit"
commit small.txt
expect_blocked "commit <path> with that file"
git -C "$repo" checkout -q small.txt

echo "every offender is listed"
bytes one.md 21000
bytes two.md 22000
git -C "$repo" add one.md two.md
commit
expect_blocked "two over-limit files"
expect_line "two offenders" "$out" "  one.md: 5250 tokens (21000 bytes). Split it into at least 2 files."
expect_line "two offenders" "$out" "  two.md: 5500 tokens (22000 bytes). Split it into at least 2 files."
rm "$repo/one.md" "$repo/two.md"

echo "a checkout without the script commits"
rm "$repo/scripts/check-token-budget.sh"
bytes three.md 21000
git -C "$repo" add three.md
commit
expect_commits "a 21000-byte file once the script is gone"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
