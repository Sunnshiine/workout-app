#!/usr/bin/env bash
# Proves scripts/prune-merged-worktrees.sh against throwaway repositories under
# $(mktemp -d), with a stubbed `gh` on PATH. Nothing here touches a real
# repository or a real GitHub account, so --apply is safe to exercise.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
prune="$script_dir/../prune-merged-worktrees.sh"
[ -x "$prune" ] || { echo "not executable: $prune" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
wt="$root/wt"
pass=0
fail=0

say() { printf '%s\n' "$*"; }
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

git_q() { git -C "$repo" "$@" >/dev/null 2>&1; }

commit_on() {
    # commit_on <branch> <file-content>
    printf '%s\n' "$2" >"$repo/$1.txt"
    git_q add -A
    git_q -c user.email=t@t -c user.name=t commit -m "$1: $2"
}

# ---------------------------------------------------------------- fixture repo
build_fixture() {
    mkdir -p "$repo" "$wt" "$root/bin"
    git -C "$root" init --bare --quiet origin.git
    git_q init -b main
    git_q config user.email t@t
    git_q config user.name t
    git_q remote add origin "$root/origin.git"
    commit_on main one
    git_q push -u origin main

    # Every branch below starts from main and is pushed, except where a case
    # needs it otherwise.
    for b in merged closed open dirty unpushed nopr squashed gone-ahead primary-merged; do
        git_q checkout -b "$b" main
        commit_on "$b" work
        case "$b" in
            nopr) : ;;                       # never pushed, and no PR will exist
            *) git_q push -u origin "$b" ;;
        esac
    done
    git_q checkout main

    # Record the pushed tips before anything is deleted; the stub PR data uses
    # them as headRefOid, the way GitHub records the SHA it received.
    : >"$root/oids.tsv"
    for b in merged closed open dirty unpushed squashed gone-ahead primary-merged; do
        printf '%s\t%s\n' "$b" "$(git -C "$repo" rev-parse "$b")" >>"$root/oids.tsv"
    done

    # case 5: one local commit the remote never received.
    git_q checkout unpushed
    commit_on unpushed "local only"
    git_q checkout main

    # case 10: upstream gone AND a local commit beyond the PR head. This is the
    # conflation the ticket warns about: [gone] must not read as "nothing lost".
    git_q checkout gone-ahead
    commit_on gone-ahead "local only"
    git_q checkout main

    # cases 9 and 10: the repo deletes merged branches, so drop the remote
    # branch and prune, leaving branch.<name>.merge configured but the
    # remote-tracking ref gone.
    git -C "$root/origin.git" branch -D squashed >/dev/null 2>&1
    git -C "$root/origin.git" branch -D gone-ahead >/dev/null 2>&1
    git_q fetch origin --prune

    # The primary checkout sits on a clean branch whose PR merged, so only the
    # primary-checkout guard can save it.
    git_q checkout primary-merged

    for b in merged closed open dirty unpushed nopr squashed gone-ahead; do
        git -C "$repo" worktree add "$wt/$b" "$b" >/dev/null 2>&1
    done
    git -C "$repo" worktree add --detach "$wt/detached" main >/dev/null 2>&1

    # case 4: uncommitted change in a worktree whose PR merged.
    printf 'edited\n' >>"$wt/dirty/dirty.txt"
}

oid() { awk -F '\t' -v b="$1" '$1 == b { print $2; exit }' "$root/oids.tsv"; }

build_gh_stub() {
    # The stub answers any `gh pr list ... --json ...` with fixed data, so the
    # script exercises its real invocation and parsing path.
    jq -n \
      --arg merged "$(oid merged)" --arg closed "$(oid closed)" --arg open "$(oid open)" \
      --arg dirty "$(oid dirty)" --arg unpushed "$(oid unpushed)" --arg squashed "$(oid squashed)" \
      --arg goneahead "$(oid gone-ahead)" --arg primarymerged "$(oid primary-merged)" \
      '[ {number:1,  state:"MERGED", headRefName:"merged",         headRefOid:$merged},
         {number:2,  state:"CLOSED", headRefName:"closed",         headRefOid:$closed},
         {number:3,  state:"OPEN",   headRefName:"open",           headRefOid:$open},
         {number:4,  state:"MERGED", headRefName:"dirty",          headRefOid:$dirty},
         {number:5,  state:"MERGED", headRefName:"unpushed",       headRefOid:$unpushed},
         {number:9,  state:"MERGED", headRefName:"squashed",       headRefOid:$squashed},
         {number:10, state:"MERGED", headRefName:"gone-ahead",     headRefOid:$goneahead},
         {number:8,  state:"MERGED", headRefName:"primary-merged", headRefOid:$primarymerged} ]' \
      >"$root/prs.json"

    cat >"$root/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub. Only `gh pr list --json ...` is used by the script under test.
case "$1 ${2:-}" in
    "pr list") cat "$GH_STUB_PRS" ;;
    *) echo "gh stub: unexpected command: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "$root/bin/gh"
}

# ---------------------------------------------------------------- assertions
candidates() { awk '/^CANDIDATES$/{f=1;next} /^KEPT$/{f=0} f' "$root/out.txt"; }
kept()       { awk '/^KEPT$/{f=1;next} f' "$root/out.txt"; }

assert_candidate() {
    # assert_candidate <case> <branch>
    if candidates | awk -v b="$2" '$1==b{found=1} END{exit !found}'; then
        ok "$1: $2 listed as a candidate"
    else
        bad "$1: $2 missing from CANDIDATES"
    fi
}

assert_kept() {
    # assert_kept <case> <branch> <reason substring>
    local line
    line=$(kept | awk -v b="$2" '$1==b')
    if [ -z "$line" ]; then
        bad "$1: $2 missing from KEPT"
    elif printf '%s' "$line" | grep -qF -- "$3"; then
        ok "$1: $2 kept ($3)"
    else
        bad "$1: $2 kept for the wrong reason: $line"
    fi
}

assert_column() {
    # assert_column <case> <branch> <expected field value>
    if candidates | awk -v b="$2" -v v="$3" '$1==b { for(i=1;i<=NF;i++) if($i==v) found=1 } END{exit !found}'; then
        ok "$1: $2 reported as $3"
    else
        bad "$1: $2 not reported as $3: $(candidates | awk -v b="$2" '$1==b')"
    fi
}

assert_gone() {
    if git -C "$repo" worktree list | grep -qF "$wt/$2"; then
        bad "$1: worktree $2 survived --apply"
    elif [ -n "$(git -C "$repo" branch --list "$2")" ]; then
        bad "$1: branch $2 survived --apply"
    else
        ok "$1: worktree and branch $2 removed by --apply"
    fi
}

assert_survives() {
    if git -C "$repo" worktree list | grep -qF "$wt/$2"; then
        ok "$1: worktree $2 survived --apply"
    else
        bad "$1: worktree $2 was removed by --apply"
    fi
}

# ---------------------------------------------------------------- run
build_fixture
build_gh_stub
export GH_STUB_PRS="$root/prs.json"
export PATH="$root/bin:$PATH"

say "fixture: $root"
say
say "=== dry run (default) ==="
"$prune" --repo "$repo" --no-size >"$root/out.txt" 2>"$root/err.txt"
dry_status=$?
cat "$root/out.txt"
if [ -s "$root/err.txt" ]; then say "stderr:"; cat "$root/err.txt"; fi
say
say "--- dry-run assertions ---"
if [ "$dry_status" -eq 0 ]; then ok "dry run exits 0"; else bad "dry run exited $dry_status"; fi
assert_candidate "case 1 merged PR"           merged
assert_candidate "case 2 closed PR"           closed
assert_kept      "case 3 open PR"             open       "is open"
assert_kept      "case 4 uncommitted"         dirty      "uncommitted changes"
assert_kept      "case 5 unpushed commits"    unpushed   "commits the PR never received"
assert_kept      "case 6 no PR"               nopr       "no pull request"
assert_kept      "case 7 detached HEAD"       -          "detached HEAD"
assert_kept      "case 8 primary checkout"    primary-merged "primary checkout"
assert_candidate "case 9 upstream gone"       squashed
assert_column    "case 9 upstream gone"       squashed   "gone=pr-head"
assert_kept      "case 10 gone plus local"    gone-ahead "commits the PR never received"

before=$(git -C "$repo" worktree list | wc -l | tr -d ' ')
say
say "=== the same run with --apply ==="
"$prune" --repo "$repo" --no-size --apply >"$root/apply.txt" 2>&1
apply_status=$?
cat "$root/apply.txt"
say
say "--- apply assertions ---"
if [ "$apply_status" -eq 0 ]; then ok "apply exits 0"; else bad "apply exited $apply_status"; fi
assert_gone     "case 1 merged PR"        merged
assert_gone     "case 2 closed PR"        closed
assert_gone     "case 9 upstream gone"    squashed
assert_survives "case 3 open PR"          open
assert_survives "case 4 uncommitted"      dirty
assert_survives "case 5 unpushed commits" unpushed
assert_survives "case 6 no PR"            nopr
assert_survives "case 7 detached HEAD"    detached
assert_survives "case 10 gone plus local" gone-ahead
if [ -d "$repo/.git" ] && [ -n "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" ]; then
    ok "case 8 primary checkout: repository intact after --apply"
else
    bad "case 8 primary checkout: repository destroyed"
fi
after=$(git -C "$repo" worktree list | wc -l | tr -d ' ')
if [ "$after" -eq $((before - 3)) ]; then
    ok "git worktree list dropped from $before to $after"
else
    bad "git worktree list went $before -> $after, expected $((before - 3))"
fi

say
say "=== second --apply run is a no-op ==="
"$prune" --repo "$repo" --no-size --apply >"$root/apply2.txt" 2>&1
grep -E '^(worktrees:|CANDIDATES)' -A1 "$root/apply2.txt" | head -4
if grep -qE 'worktrees: [0-9]+ examined, 0 to remove' "$root/apply2.txt"; then
    ok "rerun finds nothing left to remove"
else
    bad "rerun still reports candidates"
fi

say
say "=== gh unavailable keeps everything ==="
PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$prune" --repo "$repo" --no-size >"$root/nogh.txt" 2>&1
if grep -qE 'worktrees: [0-9]+ examined, 0 to remove' "$root/nogh.txt"; then
    ok "no gh on PATH removes nothing"
else
    bad "no gh on PATH still produced candidates"
    cat "$root/nogh.txt"
fi

say
say "=== gh present but failing keeps everything ==="
mkdir -p "$root/failbin"
printf '#!/usr/bin/env bash\necho "HTTP 429 rate limit exceeded" >&2\nexit 1\n' >"$root/failbin/gh"
chmod +x "$root/failbin/gh"
PATH="$root/failbin:$PATH" "$prune" --repo "$repo" --no-size >"$root/ghfail.txt" 2>&1
if grep -qE 'worktrees: [0-9]+ examined, 0 to remove' "$root/ghfail.txt" \
   && grep -q 'gh pr list failed' "$root/ghfail.txt"; then
    ok "a failing gh removes nothing and says why"
else
    bad "a failing gh did not fail safe"
    cat "$root/ghfail.txt"
fi

# A second repository, because the first has no candidates left. Two clean
# worktrees whose PRs both merged; the race below targets the one removed last.
race_repo="$root/race"
race_wt="$root/race-wt"
mkdir -p "$race_repo"
git -C "$root" init --bare --quiet race-origin.git
git -C "$race_repo" init -q -b main
git -C "$race_repo" config user.email t@t
git -C "$race_repo" config user.name t
git -C "$race_repo" remote add origin "$root/race-origin.git"
printf 'base\n' >"$race_repo/base.txt"
git -C "$race_repo" add -A
git -C "$race_repo" commit -qm base
git -C "$race_repo" push -q -u origin main
for b in aaa-first zzz-second; do
    git -C "$race_repo" checkout -q -b "$b" main
    printf '%s\n' "$b" >"$race_repo/$b.txt"
    git -C "$race_repo" add -A
    git -C "$race_repo" commit -qm "$b"
    git -C "$race_repo" push -q -u origin "$b"
done
git -C "$race_repo" checkout -q main
jq -n --arg a "$(git -C "$race_repo" rev-parse aaa-first)" \
      --arg z "$(git -C "$race_repo" rev-parse zzz-second)" \
   '[{number:20,state:"MERGED",headRefName:"aaa-first",headRefOid:$a},
     {number:21,state:"MERGED",headRefName:"zzz-second",headRefOid:$z}]' >"$root/race-prs.json"
for b in aaa-first zzz-second; do
    git -C "$race_repo" worktree add "$race_wt/$b" "$b" >/dev/null 2>&1
done

say
say "=== size column is populated without --no-size ==="
GH_STUB_PRS="$root/race-prs.json" "$prune" --repo "$race_repo" >"$root/size.txt" 2>&1
if awk '/^CANDIDATES$/{f=1;next} /^KEPT$/{f=0} f' "$root/size.txt" \
   | awk 'NR>1 && NF { if ($4 == "-") bad=1 } END { exit bad }'; then
    ok "every candidate reports a size on disk"
else
    bad "a candidate reported no size"
    cat "$root/size.txt"
fi

say
say "=== a commit landing between the scan and the removal ==="
# The wrapper injects the race from outside, so the script under test runs
# unmodified: on its first `git worktree remove` it commits into the worktree
# the apply loop has not reached yet.
mkdir -p "$root/racebin"
cat >"$root/racebin/git" <<'WRAP'
#!/usr/bin/env bash
if [ "${1:-}" = worktree ] && [ "${2:-}" = remove ] && [ ! -f "$RACE_FLAG" ]; then
    : >"$RACE_FLAG"
    printf 'raced
' >"$RACE_TARGET/raced.txt"
    "$REAL_GIT" -C "$RACE_TARGET" add -A
    "$REAL_GIT" -C "$RACE_TARGET" -c user.email=t@t -c user.name=t commit -qm "landed mid-apply"
fi
exec "$REAL_GIT" "$@"
WRAP
chmod +x "$root/racebin/git"
REAL_GIT=$(command -v git) \
RACE_TARGET="$race_wt/zzz-second" \
RACE_FLAG="$root/raced.flag" \
GH_STUB_PRS="$root/race-prs.json" \
PATH="$root/racebin:$PATH" \
    "$prune" --repo "$race_repo" --no-size --apply >"$root/race.txt" 2>&1
race_status=$?
cat "$root/race.txt"
say
raced_sha=$(git -C "$race_wt/zzz-second" rev-parse HEAD 2>/dev/null)
if [ -d "$race_wt/aaa-first" ]; then
    bad "race: aaa-first was not removed, so the race never reached the loop"
else
    ok "race: aaa-first removed as planned"
fi
if [ -d "$race_wt/zzz-second" ] && [ -f "$race_wt/zzz-second/raced.txt" ]; then
    ok "race: zzz-second survived with its mid-apply commit intact ($raced_sha)"
else
    bad "race: zzz-second and its mid-apply commit were destroyed"
fi
if [ -n "$(git -C "$race_repo" branch --list zzz-second)" ]; then
    ok "race: branch zzz-second was not force-deleted"
else
    bad "race: branch zzz-second was force-deleted, losing the commit"
fi
if grep -q 'SKIPPED: HEAD moved' "$root/race.txt"; then
    ok "race: the skip is reported with its reason"
else
    bad "race: no SKIPPED line explaining the refusal"
fi
if [ "$race_status" -ne 0 ]; then
    ok "race: a partial run exits non-zero ($race_status)"
else
    bad "race: a partial run exited 0"
fi

say
say "passed $pass, failed $fail"
[ "$fail" -eq 0 ] || exit 1
