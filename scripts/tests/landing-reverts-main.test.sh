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

new_repo() {
    git init -q -b main "$1"
    cd "$1" || exit 3
    git config user.email test@example.com
    git config user.name test
    git config commit.gpgsign false
}

repo="$root/repo"
new_repo "$repo"
git remote add origin https://github.com/Sunnshiine/workout-app.git

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
printf 'Reverts #10, #2\n' >"$root/body"
expect "one Reverts line that lists two PRs allows both" 0 "" "$main" "$revert" --body-file "$root/body"
printf 'reverts: #2\n' >"$root/body"
expect "a lowercase Reverts with a colon" 0 "" "$main" "$revert" --body-file "$root/body"
printf 'Reverts other/repo#2\n' >"$root/body"
expect "Reverts other/repo#2 names another repository's #2, so it still fires" 1 "undoes #2" \
    "$main" "$revert" --body-file "$root/body"
printf 'To declare a revert, write:\n\n```text\nReverts #2\n```\n\n~~~\nReverts #2\n~~~\n\n    Reverts #2\n' >"$root/body"
expect "Reverts #2 inside a fenced or indented code block is an example, so it still fires" 1 "undoes #2" \
    "$main" "$revert" --body-file "$root/body"
git remote set-url origin git@github.com:Sunnshiine/workout-app.git
printf 'Reverts sunnshiine/Workout-App#2\n' >"$root/body"
expect "the owner/repo form matches an ssh origin, whatever the case" 0 "" "$main" "$revert" --body-file "$root/body"
git remote set-url origin "file://$repo"
expect "with no GitHub origin, the owner/repo form allows nothing" 1 "undoes #2" \
    "$main" "$revert" --body-file "$root/body"
git remote set-url origin https://github.com/Sunnshiine/workout-app.git

echo "normal landings stay quiet"
expect "a clean merge of main says it checked the window" 0 "quiet: " "$main" "$clean_merge"
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

mkdir -p "$root/failing-merge-tree"
cat >"$root/failing-merge-tree/git" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do
    [ "\$arg" = merge-tree ] && { echo "fatal: simulated merge-tree failure" >&2; exit 128; }
done
exec "$real_git" "\$@"
STUB
chmod +x "$root/failing-merge-tree/git"
got=$(PATH="$root/failing-merge-tree:$PATH" run "$main" "$conflict")
if [ "$got" = 2 ] && grep -q "git merge-tree failed: fatal: simulated merge-tree failure" "$root/err"; then
    ok "a merge-tree that fails for another reason exits 2 and says so"
else
    bad "a merge-tree that fails for another reason exits 2 and says so: exit $got, $(cat "$root/out" "$root/err")"
fi

echo "a deleted line belongs to the commit that added that line, not to any commit with the same text"
new_repo "$root/copy"
{ feature_lines old 12; feature_lines spacer 6; } >old.txt
commit "feat: old block (#20)"
for i in 21 22 23; do echo "filler $i" >"filler$i.txt"; commit "chore: filler (#$i)"; done
git checkout -q -b drop-old-block
sed -i.bak 1,12d old.txt && rm old.txt.bak
commit "refactor: drop the old block"
git checkout -q main
feature_lines old 12 >>old.txt
commit "feat: a copy of the old block at the end (#300)"
expect "a branch that deletes an old block is quiet after main appends a copy of it" 0 "quiet: " \
    main drop-old-block --window 3

echo "a merge that drops one file of a commit that touched three fires"
new_repo "$root/three-files"
for f in g1 g2 g3; do echo "$f base line" >"$f.txt"; done
commit "base (#1)"
git checkout -q -b drops-g1
echo "branch work" >b.txt
commit "branch work"
git checkout -q main
for f in g1 g2 g3; do feature_lines "$f" 30 >>"$f.txt"; done
commit "feat: three files (#7)"
git checkout -q drops-g1
git merge -q --no-ff --no-commit main >/dev/null
git checkout main~1 -- g1.txt
git commit -q -m "Merge main"
expect "the merge's silent drop of g1.txt names #7 and the file" 1 "undoes #7 30/90 lines" main drops-g1

echo "a merge commit on the base"
new_repo "$root/base-merge"
echo "shared line one here" >a.txt
commit "base (#1)"
git checkout -q -b side
echo "side version line" >a.txt
commit "side (#2)"
git checkout -q main
echo "main version line" >a.txt
commit "main (#3)"
git merge -q side -m "Merge side" >/dev/null 2>&1
echo "resolved version line" >a.txt
commit "Merge side (#4)"
git checkout -q -b on-merge
echo "pr work" >p.txt
commit "pr work"
git checkout -q main
echo "main later work" >m.txt
commit "later (#5)"
got=$(run main on-merge)
if [ "$got" = 0 ] && [ ! -s "$root/err" ]; then
    ok "a base whose window holds a merge that resolved a conflict is read, and stays quiet"
else
    bad "a base whose window holds a merge that resolved a conflict is read, and stays quiet: exit $got, $(tail -3 "$root/err")"
fi

echo "a commit with no PR number"
new_repo "$root/no-number"
echo "base" >a.txt
commit "base"
feature_lines direct 12 >>a.txt
commit "chore: pushed straight to main"
direct=$(git rev-parse HEAD)
git checkout -q -b revert-direct
git revert --no-edit HEAD >/dev/null
expect "a revert of a commit with no PR number names its short SHA" 1 "undoes ${direct:0:8} 12/12 lines" \
    main revert-direct
printf 'Reverts %s\n' "${direct:0:7}" >"$root/body"
expect "Reverts <sha> allows it" 0 "" main revert-direct --body-file "$root/body"

echo "paths that git writes with a trailing tab or in quotes"
for path in "my file.txt" "my dir/f.txt" 'say "hi".txt'; do
    new_repo "$root/path-$(echo "$path" | tr -c 'a-z' -)"
    echo "base" >base.txt
    commit "base (#1)"
    mkdir -p "$(dirname "$path")"
    feature_lines odd 12 >"$path"
    commit "feat: odd path (#5)"
    git checkout -q -b revert-odd
    git revert --no-edit HEAD >/dev/null
    expect "a revert in '$path' names #5 and the path" 1 "  $path (12 lines)" main revert-odd
    printf 'Reverts #5\n' >"$root/body"
    expect "Reverts #5 allows the revert in '$path'" 0 "" main revert-odd --body-file "$root/body"
done

echo "content that is not UTF-8"
new_repo "$root/latin1"
echo "base" >a.txt
commit "base (#1)"
git checkout -q -b branch-work
echo "branch work" >b.txt
commit "branch work"
git checkout -q main
for i in 1 2 3 4 5 6; do printf 'caf\351 au lait line %s\n' "$i"; done >menu.txt
commit "feat: a Latin-1 menu (#4)"
git checkout -q branch-work
git merge -q --no-edit main
got=$(run main branch-work)
if [ "$got" = 0 ] && [ ! -s "$root/err" ]; then
    ok "a Latin-1 file on the base is read, and a clean merge stays quiet"
else
    bad "a Latin-1 file on the base is read, and a clean merge stays quiet: exit $got, $(tail -3 "$root/err")"
fi

echo "a shallow clone whose fetch depth stops above the merge base"
new_repo "$root/far-behind"
echo "base" >a.txt
commit "base (#1)"
git checkout -q -b old-branch
echo "branch work" >b.txt
commit "branch work"
git checkout -q main
for i in 2 3 4 5 6 7 8; do echo "main $i" >"m$i.txt"; commit "chore: main $i (#$i)"; done
git init -q "$root/far-behind-ci"
got=$(cd "$root/far-behind-ci" && git fetch -q --depth=3 "file://$root/far-behind" main old-branch 2>&1 \
    && run "$(git -C "$root/far-behind" rev-parse main)" "$(git -C "$root/far-behind" rev-parse old-branch)" --window 2)
if [ "$got" = 3 ] && grep -q "share no commit here" "$root/err"; then
    ok "a merge base past the fetch depth exits 3, so CI fetches deeper"
else
    bad "a merge base past the fetch depth exits 3, so CI fetches deeper: exit $got, $(cat "$root/out" "$root/err")"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
