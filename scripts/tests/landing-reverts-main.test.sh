#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check_script="$script_dir/../landing-reverts-main.py"
[ -x "$check_script" ] || { echo "not executable: $check_script" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

repo="$root/repo"
git init -q -b main "$repo"
cd "$repo" || exit 3
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false

feature_lines() { for i in $(seq "$2"); do echo "feature $1 line $i"; done; }

commit() { git add -A && git commit -q -m "$1"; }

printf 'header of the file\nfooter of the file\n' >a.txt
echo "branch work starts here" >b.txt
commit "base (#1)"
fork=$(git rev-parse HEAD)
{ echo "header of the file"; feature_lines alpha 12; echo "footer of the file"; } >a.txt
commit "feat: alpha (#2)"
main=$(git rev-parse HEAD)

on_branch() {
    git checkout -q -B "$1" "$2"
}

on_branch keeps-branch-side "$fork"
echo "branch work continues" >>b.txt
commit "branch work"
git merge -q -s ours --no-edit main
keeps_branch_side=$(git rev-parse HEAD)

on_branch clean-merge "$fork"
echo "branch work continues" >>b.txt
commit "branch work"
git merge -q --no-edit main
clean_merge=$(git rev-parse HEAD)

on_branch revert "$main"
git revert --no-edit HEAD >/dev/null
revert=$(git rev-parse HEAD)

stale_squash=$(git commit-tree "$keeps_branch_side^{tree}" -p "$main" -m "squash of a stale tree")

on_branch own-edit "$main"
{ echo "header of the file"; feature_lines alpha 12 | sed 1,5d; echo "footer of the file"; } >a.txt
commit "refactor: drop five alpha lines"
own_edit=$(git rev-parse HEAD)

on_branch move "$main"
printf 'header of the file\nfooter of the file\n' >a.txt
feature_lines alpha 12 >c.txt
commit "refactor: move alpha into c.txt"
move=$(git rev-parse HEAD)

on_branch conflict "$fork"
printf 'header of the file, retitled\nfooter of the file\n' >a.txt
commit "retitle the header"
conflict=$(git rev-parse HEAD)

git checkout -q main

run() {
    "$check_script" "$@" >"$root/out" 2>"$root/err"
    echo $?
}

expect() {
    local name=$1 want=$2 grep_for=$3
    shift 3
    local got
    got=$(run "$@")
    if [ "$got" = "$want" ] && { [ -z "$grep_for" ] || grep -qF -- "$grep_for" "$root/out" "$root/err"; }; then
        ok "$name"
    else
        bad "$name"
        printf 'want exit %s and %s, got exit %s\n' "$want" "${grep_for:-no text}" "$got" | sed 's/^/       /'
        sed 's/^/       out: /' "$root/out"
        sed 's/^/       err: /' "$root/err"
    fi
}

echo "a landing that undoes main fires"
expect "a merge that keeps the branch side of main's change names #2 and its lines" 1 \
    "undoes #2 12/12 lines" "$main" "$keeps_branch_side"
expect "the finding names the file it undoes" 1 "  a.txt (12 lines)" "$main" "$keeps_branch_side"
expect "a stale tree squashed onto newer main fires though its own commit made the edit" 1 \
    "undoes #2 12/12 lines" "$main" "$stale_squash"
expect "a revert with no Reverts line fires" 1 "undoes #2" "$main" "$revert"
expect "a finding says how to declare a deliberate revert" 1 "Reverts #N" "$main" "$revert"

echo "a deliberate revert passes when the body names it"
printf 'Restores the old alpha.\n\nReverts #2\n' >"$root/body"
expect "Reverts #2 on a line of the body" 0 "" "$main" "$revert" --body-file "$root/body"
printf 'Reverts Sunnshiine/workout-app#2\n' >"$root/body"
expect "GitHub's Reverts owner/repo#2 form" 0 "" "$main" "$revert" --body-file "$root/body"
printf 'Reverts #3\nThis is not Reverts #2 at the start of a line.\n' >"$root/body"
expect "a body that names another PR, or names #2 mid-line, still fires" 1 "undoes #2" \
    "$main" "$revert" --body-file "$root/body"
expect "--allow 2" 0 "" "$main" "$revert" --allow 2

echo "normal landings stay quiet"
expect "a clean merge of main" 0 "" "$main" "$clean_merge"
expect "the PR's own commit that drops 5 of main's 12 lines" 0 "" "$main" "$own_edit"
expect "the same edit under --strict, which drops the own-commit exemption" 1 "undoes #2 5/12 lines" \
    "$main" "$own_edit" --strict
expect "a move of main's lines into another file" 0 "" "$main" "$move"

echo "the check refuses to guess"
expect "a landing that conflicts exits 2 and names the file" 2 "in a.txt" "$main" "$conflict"

mkdir -p "$root/old-git"
real_git=$(command -v git)
cat >"$root/old-git/git" <<STUB
#!/usr/bin/env bash
[ "\$1" = version ] && { echo "git version 2.37.1"; exit 0; }
exec "$real_git" "\$@"
STUB
chmod +x "$root/old-git/git"
got=$(PATH="$root/old-git:$PATH" run "$main" "$keeps_branch_side")
if [ "$got" = 2 ] && grep -q "needs git 2.38 or later.*2.37.1" "$root/err"; then
    ok "git older than 2.38 exits 2 and names the version it needs"
else
    bad "git older than 2.38 exits 2 and names the version it needs: exit $got, $(cat "$root/err")"
fi

git clone -q --depth 2 --branch keeps-branch-side "file://$repo" "$root/shallow" 2>/dev/null
got=$(cd "$root/shallow" && run "$main" "$keeps_branch_side")
if [ "$got" = 3 ] && grep -q "too shallow" "$root/err"; then
    ok "a shallow clone that lacks a parent exits 3, not a false finding"
else
    bad "a shallow clone that lacks a parent exits 3, not a false finding: exit $got, $(cat "$root/out" "$root/err")"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
