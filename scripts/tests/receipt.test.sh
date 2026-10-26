#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
receipt="$script_dir/../receipt.sh"
check="$script_dir/../check-receipts.py"
for s in "$receipt" "$check"; do
    [ -x "$s" ] || { echo "not executable: $s" >&2; exit 2; }
done

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect_exit() {
    if [ "$2" -eq "$3" ]; then ok "$1 exits $3"; else bad "$1 exits $3, got $2: $out"; fi
}

expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1: $3"; else bad "$1 is missing the line: $3, got: $2"; fi
}

expect_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then ok "$1 says: $3"; else bad "$1 does not say: $3, got: $2"; fi
}

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GITHUB_ACTIONS RECEIPT_FILE

repo="$root/repo"
git init -q -b main "$repo"
cd "$repo" || exit 3
commit() { git add -A && git commit -q -m "$1"; }

echo "let a = 1" >a.swift
commit "base (#1)"
base=$(git rev-parse HEAD)
git checkout -q -b feature
echo "let b = 2" >b.swift
commit "feat: b"

# Runs receipt.sh in the repo and leaves its stdout in $out, its status in $status, and the
# receipt file's newest block in $block.
make_receipt() {
    rm -f "$root/receipts.md"
    out=$(RECEIPT_FILE="$root/receipts.md" "$receipt" "$@" 2>/dev/null)
    status=$?
    block=$(cat "$root/receipts.md" 2>/dev/null)
}

body_with() { printf 'Some prose.\n\n%s\n' "$1" >"$root/body"; }

run_check() {
    out=$("$check" -C "$repo" --body-file "$root/body" --head "$(git rev-parse HEAD)" "$@" 2>&1)
    status=$?
}

echo "a fresh receipt names the head, and the check passes it"
mkdir "$root/bin"
cat >"$root/bin/swift" <<'EOF'
#!/bin/sh
echo "Executed 2 tests, with 0 failures (0 unexpected) in 0.1 seconds"
printf '\033[1m\342\227\207 Test run with 3 tests in 1 suite passed after 0.2 seconds.\033[0m\n'
EOF
chmod +x "$root/bin/swift"
PATH="$root/bin:$PATH" make_receipt unit -- swift test
head=$(git rev-parse HEAD)
expect_exit "receipt.sh on a passing command" "$status" 0
expect_line "the receipt" "$block" "sha: $head"
expect_line "the receipt" "$block" "dirty: no"
expect_line "the receipt" "$block" "exit: 0"
expect_line "the receipt" "$block" "summary: ◇ Test run with 3 tests in 1 suite passed after 0.2 seconds."
expect_line "the receipt" "$block" "command: swift test"
expect_text "receipt.sh's stdout" "$out" "Test run with 3 tests"
expect_text "receipt.sh's stdout" "$out" '```receipt'
if git status --porcelain | grep -q .; then bad "the default receipt file dirties the tree"; else
    "$receipt" quiet -- true >/dev/null 2>&1
    if [ -z "$(git status --porcelain)" ] && grep -q "name: quiet" "$(git rev-parse --git-path receipts.md)"; then
        ok "the default receipt file sits in the git directory, outside git status"
    else bad "the default receipt file is in the tree or missing"; fi
fi
fresh=$block
body_with "$fresh"
run_check
expect_exit "a fresh receipt" "$status" 0
expect_text "a fresh receipt" "$out" "1 receipt(s) match the head ${head:0:12}"

echo "a docs-only commit after the receipt keeps it valid"
mkdir -p docs && echo "notes" >docs/notes.txt && echo "# Guide" >docs/guide.md
commit "docs: notes"
run_check
expect_exit "a receipt older than a docs-only commit" "$status" 0

echo "a rebase onto a docs-only commit keeps it valid, since the code it tested is unchanged"
git checkout -q main && mkdir -p docs && echo "# Main" >docs/main.md && commit "docs: main (#4)" && git checkout -q feature
git rebase -q main
if git merge-base --is-ancestor "$head" HEAD; then bad "the rebase kept the receipt's commit"; else
    run_check
    expect_exit "a receipt from before a rebase onto a docs-only commit" "$status" 0
fi

echo "a code commit after the receipt makes it stale, and the error names it and both SHAs"
echo "let c = 3" >c.swift
commit "feat: c"
new_head=$(git rev-parse HEAD)
run_check
expect_exit "a stale receipt" "$status" 1
expect_text "a stale receipt" "$out" "receipt unit at ${head:0:12} is stale: the head ${new_head:0:12} changes code since then (c.swift)"
GITHUB_ACTIONS=true run_check
expect_text "a stale receipt under GitHub Actions" "$out" "::error::receipt unit at ${head:0:12}"

echo "a merge of the base brings its code in, so it makes the receipt stale too"
make_receipt unit -- true
body_with "$block"
git checkout -q main && echo "let m = 4" >m.swift && commit "feat: m (#2)" && git checkout -q feature
git merge -q --no-edit main
run_check
expect_exit "a receipt from before a merge of the base" "$status" 1
expect_text "a receipt from before a merge of the base" "$out" "m.swift"

echo "a dirty tree makes a dirty receipt, and the check fails it"
echo "let d = 4" >d.swift
make_receipt unit -- true
rm d.swift
expect_line "the receipt" "$block" "dirty: yes"
body_with "$block"
run_check
expect_exit "a dirty receipt" "$status" 1
expect_text "a dirty receipt" "$out" "receipt unit at $(git rev-parse --short=12 HEAD) ran on a dirty tree"

echo "a failing command's receipt records its status, and receipt.sh exits with it"
make_receipt red -- sh -c 'echo "broke"; exit 7'
expect_exit "receipt.sh on a command that exits 7" "$status" 7
expect_line "the receipt" "$block" "exit: 7"
expect_line "the receipt" "$block" "summary: broke"

echo "a SHA the repository lacks, a SHA off the branch with other code, and a receipt missing a field all fail"
body_with "$(printf '```receipt\nname: unit\ncommand: swift test\nsha: 66b1d37\ndirty: no\nexit: 0\n```')"
run_check
expect_exit "a SHA the repository lacks" "$status" 1
expect_text "a SHA the repository lacks" "$out" "receipt unit names 66b1d37, which is not a commit in this repository"
git checkout -q -b elsewhere "$base" && echo "x" >x.swift && commit "elsewhere" && off=$(git rev-parse HEAD) && git checkout -q feature
body_with "$(printf '```receipt\nname: unit\ncommand: swift test\nsha: %s\ndirty: no\nexit: 0\n```' "$off")"
run_check
expect_exit "a SHA off the branch" "$status" 1
expect_text "a SHA off the branch" "$out" "changes code since then (b.swift, c.swift, m.swift, and 1 more)"
body_with "$(printf '```receipt\nname: unit\ncommand: swift test\nexit: 0\n```')"
run_check
expect_exit "a receipt missing fields" "$status" 1
expect_text "a receipt missing fields" "$out" "receipt unit lacks sha, dirty"

echo "a body with no receipt passes"
printf 'No receipts here.\n' >"$root/body"
run_check
expect_exit "a body with no receipt" "$status" 0

echo "a closing keyword in a commit that the body does not repeat fails, and passes once the body closes it"
git commit -q --allow-empty -m "fix: the thing" -m "Fixes #812"
fixer=$(git rev-parse --short=12 HEAD)
printf 'Closes #5.\n' >"$root/body"
run_check --base main
expect_exit "a commit that fixes #812 under a body that does not" "$status" 1
expect_text "a commit that fixes #812 under a body that does not" "$out" "commit $fixer says \"Fixes #812\", and the body closes no #812"
printf 'This PR fixes: #812.\n' >"$root/body"
run_check --base main
expect_exit "a body that also fixes #812" "$status" 0
printf 'Mentions #812 without closing it.\n' >"$root/body"
run_check
expect_exit "the closing check without --base" "$status" 0

echo "a closing keyword already on the base is not the branch's"
git checkout -q main && git commit -q --allow-empty -m "fix: on main (#3)" -m "Closes #900" && git checkout -q feature
git merge -q --no-edit main
printf 'Fixes #812\n' >"$root/body"
run_check --base main
expect_exit "a base commit's Closes #900 merged into the branch" "$status" 0

# Prints a receipt block: rcpt NAME SHA [EXIT] [DIRTY] [COMMAND]
rcpt() {
    printf '```receipt\nname: %s\ncommand: %s\nsha: %s\ndirty: %s\nexit: %s\nsummary: 1 passed, 0 failed\n```\n' \
        "$1" "${5:-swift test}" "$2" "${4:-no}" "${3:-0}"
}

expect_pass() { body_with "$2"; run_check "${@:3}"; expect_exit "$1" "$status" 0; }
expect_fail() {
    body_with "$2"; run_check "${@:4}"
    expect_exit "$1" "$status" 1
    expect_text "$1" "$out" "$3"
}

echo "exit: a receipt whose exit is not the integer 0 fails"
h=$(git rev-parse HEAD)
expect_fail "exit: a receipt that records exit 1" "$(rcpt unit "$h" 1)" "receipt unit at ${h:0:12} records exit 1"
expect_fail "exit: a receipt that records exit 00" "$(rcpt unit "$h" 00)" "records exit 00"
expect_fail "exit: a receipt that records exit abc" "$(rcpt unit "$h" abc)" "records exit abc"
expect_pass "exit: a receipt that records exit 0" "$(rcpt unit "$h" 0)"

echo "missing fields: each field a receipt lacks fails it by name"
for f in name command sha dirty exit; do
    expect_fail "missing fields: a receipt without $f" "$(rcpt unit "$h" | grep -v "^$f: ")" "lacks $f"
done

echo "docs/: only docs/ is exempt, and never for a receipt named lint"
git checkout -q -b exempt
edit_after_receipt() {
    local name=$1 path=$2
    shift 2
    r=$(rcpt "$name" "$(git rev-parse HEAD)")
    mkdir -p "$(dirname "$path")" && echo "$*" >>"$path" && commit "edit $path"
}
edit_after_receipt unit docs/TESTING.md "a note"
expect_pass "docs/: a unit receipt across a docs/ commit" "$r"
edit_after_receipt lint docs/TESTING.md "a note"
expect_fail "docs/: a lint receipt across a docs/ commit" "$r" "receipt lint at"
edit_after_receipt unit .agents/skills/verify/launch-flags.md "| -NEW_FLAG | bool |"
expect_fail "docs/: a unit receipt across a launch-flags.md change" "$r" "(.agents/skills/verify/launch-flags.md)"
edit_after_receipt unit README.md "# Readme"
expect_fail "docs/: a unit receipt across a root README.md change" "$r" "(README.md)"
edit_after_receipt unit docsX/a.txt "x"
expect_fail "docs/: a unit receipt across a docsX/ change" "$r" "(docsX/a.txt)"
edit_after_receipt unit foomd "x"
expect_fail "docs/: a unit receipt across a change to foomd" "$r" "(foomd)"
r=$(rcpt unit "$(git rev-parse HEAD)")
mkdir -p docs && git mv b.swift docs/b.swift && commit "move b.swift into docs/"
expect_fail "docs/: a unit receipt across a rename of code into docs/" "$r" "(b.swift)"
git checkout -q feature

echo "closing: Closes, Resolves, and the same repository's owner/repo#N or issue URL repeat a commit's Fixes #7"
git checkout -q -b closing "$base"
git commit -q --allow-empty -m "fix: seven" -m "Fixes #7"
closing() { GITHUB_REPOSITORY=acme/app "$@" --base main; }
expect_closing_pass() { body_with "$2"; closing run_check; expect_exit "$1" "$status" 0; }
expect_closing_fail() {
    body_with "$2"; closing run_check
    expect_exit "$1" "$status" 1
    expect_text "$1" "$out" "${3:-and the body closes no #7}"
}
expect_closing_pass "closing: a body that says Closes #7" "Closes #7"
expect_closing_pass "closing: a body that says resolved: #7" "resolved: #7"
expect_closing_pass "closing: a body that says Fixes acme/app#7" "Fixes acme/app#7"
expect_closing_pass "closing: a body that says Fixes ACME/App#7" "Fixes ACME/App#7"
expect_closing_pass "closing: a body that says Fixes https://github.com/acme/app/issues/7" "Fixes https://github.com/acme/app/issues/7"
expect_closing_fail "closing: a body that closes other/repo#7" "Fixes other/repo#7"
expect_closing_fail "closing: a body that closes other/repo's issue 7 by URL" "Fixes https://github.com/other/repo/issues/7"
expect_closing_fail "closing: a body that closes #70" "Fixes #70"
expect_closing_pass "closing: a body that says closed #7" "closed #7"
expect_closing_pass "closing: a body that says fixed #7" "fixed #7"
expect_closing_fail "closing: a body that says suffixes #7" "suffixes #7"
expect_closing_fail "closing: a body that says Fixes #7a" "Fixes #7a"
expect_closing_fail "closing: a body that quotes Fixes #7 in inline code" 'The commit says `Fixes #7`.'
expect_closing_fail "closing: a body that quotes Fixes #7 in a fenced block" "$(printf '```text\nFixes #7\n```')"
expect_closing_fail "closing: a body that quotes Fixes #7 in a ~~~ block" "$(printf '~~~text\nFixes #7\n~~~')"
body_with "Fixes acme/app#7"
run_check --base main --repo acme/app
expect_exit "closing: --repo names the repository" "$status" 0
git commit -q --allow-empty -m "fix: nine" -m "closes #9" -m "Resolved: #10" -m "Fixes other/repo#11"
expect_closing_fail "closing: a commit's closes #9 under a body that omits it" "Fixes #7" "and the body closes no #9"
expect_closing_fail "closing: a commit's Resolved: #10 under a body that omits it" "Fixes #7" "and the body closes no #10"
expect_closing_fail "closing: a commit's Fixes other/repo#11 under a body that closes only #11" "Fixes #7, closes #9, resolves #10, fixes #11" "and the body closes no other/repo#11"
expect_closing_fail "closing: an earlier commit's Fixes #7 under a body that closes only the head commit's issues" "closes #9, resolves #10, fixes other/repo#11"
expect_closing_pass "closing: a body that repeats every commit keyword" "Fixes #7, closes #9, resolves #10, fixes other/repo#11"
git checkout -q feature

echo "fence: ~~~ and any info string that starts with receipt are receipts, a nested or indented one fails, and a receipt that does not parse fails"
h=$(git rev-parse HEAD)
fresh=$(rcpt unit "$h")
expect_fail "fence: a dirty receipt in a ~~~ fence" "$(rcpt unit "$h" 0 yes | sed 's/^```/~~~/')" "ran on a dirty tree"
expect_fail "fence: a dirty receipt under the info string Receipt" "$(rcpt unit "$h" 0 yes | sed 's/^```receipt/```Receipt/')" "ran on a dirty tree"
expect_fail "fence: a dirty receipt under the info string receipt,yaml" "$(rcpt unit "$h" 0 yes | sed 's/^```receipt/```receipt,yaml/')" "ran on a dirty tree"
expect_fail "fence: a receipt that says dirty: maybe" "$(rcpt unit "$h" 0 maybe)" "receipt unit at ${h:0:12} ran on a dirty tree"
body_with "$(printf '````markdown\n%s\n````' "$(rcpt unit "$h" 0 yes)")"
run_check
expect_exit "fence: a receipt quoted inside a four-backtick fence" "$status" 0
expect_text "fence: a receipt quoted inside a four-backtick fence" "$out" "0 receipt(s)"
body_with "$(printf '````markdown\n```\n%s\n````' "$(rcpt unit "$h" 0 yes)")"
run_check
expect_exit "fence: a receipt after a shorter fence line inside a four-backtick fence" "$status" 0
body_with "$(printf '~~~markdown\n```\n%s\n~~~' "$(rcpt unit "$h" 0 yes)")"
run_check
expect_exit "fence: a receipt after a backtick fence line inside a ~~~ fence" "$status" 0
expect_fail "fence: a receipt with no closing fence" "$(rcpt unit "$h" | sed '$d')" "receipt unit has no closing fence"
expect_fail "fence: a receipt with a line that is not a field" "$(rcpt unit "$h" | sed 's/^dirty: no$/dirty: no\nall good/')" "receipt unit has a line that is not a field: all good"
expect_fail "fence: a receipt that repeats a field" "$(rcpt unit "$h" | sed 's/^exit: 0$/exit: 0\nexit: 1/')" "receipt unit repeats exit"
expect_fail "fence: a receipt with an unknown field" "$(rcpt unit "$h" | sed 's/^exit: 0$/exit: 0\ntests: 3/')" "receipt unit has an unknown field tests"
expect_fail "fence: a receipt inside a quote" "$(rcpt unit "$h" | sed 's/^/> /')" "is not checked, so move it to the top level"
expect_fail "fence: a receipt in a ~~~ fence inside a quote" "$(rcpt unit "$h" | sed 's/^```/~~~/; s/^/> /')" "is not checked, so move it to the top level"
expect_fail "fence: a receipt under the info string RECEIPT inside a quote" "$(rcpt unit "$h" | sed 's/^```receipt/```RECEIPT/; s/^/> /')" "is not checked, so move it to the top level"
expect_fail "fence: a receipt in a bullet list item" "$(rcpt unit "$h" 0 yes | sed '1s/^/- /; 2,$s/^/  /')" "is not checked, so move it to the top level"
expect_fail "fence: a receipt in a numbered list item" "$(rcpt unit "$h" 0 yes | sed '1s/^/1. /; 2,$s/^/   /')" "is not checked, so move it to the top level"
expect_fail "fence: a receipt indented four spaces as a list continuation" "$(printf '1. item\n\n%s' "$(rcpt unit "$h" 0 yes | sed 's/^/    /')")" "is not checked, so move it to the top level"
expect_fail "fence: a receipt indented by a tab" "$(rcpt unit "$h" 0 yes | sed "s/^/$(printf '\t')/")" "is not checked, so move it to the top level"
body_with "$(printf '%s\n%s\n' "$fresh" "$(rcpt lint "$h")")"
run_check
expect_exit "fence: two fresh receipts in a row" "$status" 0
expect_text "fence: two fresh receipts in a row" "$out" "2 receipt(s)"
expect_fail "fence: a fresh receipt, then a dirty one" "$(printf '%s\n%s\n' "$fresh" "$(rcpt lint "$h" 0 yes)")" "receipt lint at ${h:0:12} ran on a dirty tree"
expect_pass "fence: prose after a receipt that reads like a field" "$(printf '%s\ndirty: yes\n' "$fresh")"

echo "dirty after: a command that changes the tree or HEAD writes dirty: yes"
make_receipt writes -- sh -c 'echo x >made.txt'
expect_line "dirty after: a command that writes an untracked file" "$block" "dirty: yes"
rm -f made.txt
make_receipt commits -- git commit -q --allow-empty -m "a commit the command makes"
expect_line "dirty after: a command that makes a commit" "$block" "dirty: yes"
git reset -q --hard HEAD~1
make_receipt clean -- true
expect_line "dirty after: a command that changes nothing" "$block" "dirty: no"

echo "bad arguments"
out=$("$receipt" unit swift test 2>&1)
expect_exit "receipt.sh without --" "$?" 2
out=$("$receipt" 'a b' -- true 2>&1)
expect_exit "receipt.sh with a NAME holding a space" "$?" 2
out=$("$check" -C "$repo" --body-file "$root/body" --head nosuchref 2>&1)
expect_exit "check-receipts.py on a head that does not resolve" "$?" 2

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
