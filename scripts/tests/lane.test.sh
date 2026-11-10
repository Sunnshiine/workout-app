#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/lane-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/lane-harness.sh"

lane up a "${c1:0:8}"
expect "up prints the two export lines and touches no simulator" "$status $(cat "$root/out") | $(sim_calls)" \
    "0 $(env_lines a) | "
expect "the worktree is detached at the full SHA, with Secrets.xcconfig and the evidence dir" \
    "$(git -C "$lanes/a" rev-parse HEAD) $(git -C "$lanes/a" symbolic-ref -q HEAD || echo detached) $(cat "$lanes/a/Secrets.xcconfig") $([ -d "$evidence/detached-a" ] && echo evidence)" \
    "$c1 detached CLIENT_ID = test evidence"
first=$(cat "$root/out")

lane up a "$c1"
expect "a second up prints the same lines" "$status $(cat "$root/out")" "0 $first"

lane up a "$c2"
expect "up at another commit exits 2 and names where the lane is" "$status $(cat "$root/err")" \
    "2 lane.sh: lane a is at $c1, not $c2; lane.sh down a first"

lane up b "${c3:0:10}"
expect "a commit only origin has is fetched, then the lane is made" \
    "$status $(head -1 "$root/err") | $(git -C "$lanes/b" rev-parse HEAD)" \
    "0 lane.sh: ${c3:0:10} is not here; fetching origin | $c3"

lane up p "$c4"
expect "a full SHA only a pull ref holds is fetched by SHA" "$status $(git -C "$lanes/p" rev-parse HEAD)" "0 $c4"

lane up u deadbeef
expect "an unknown commit exits 2 and creates no worktree" \
    "$status $(tail -1 "$root/err") | $(ls "$lanes" | tr '\n' ' ')" \
    "2 lane.sh: unknown commit deadbeef, even after fetching origin | a b p "

lane up "x $c1"
expect "one argument holding a name and a SHA, as zsh passes \"x <sha>\", exits 2 and creates nothing" \
    "$status $(head -1 "$root/err") | $(ls "$lanes" | tr '\n' ' ')" \
    "2 Usage: scripts/lane.sh up <name> <commit> | a b p "

"$primary/scripts/lane.sh" --help >"$root/out" 2>"$root/err"
expect "--help prints the usage on stdout and exits 0" "$? $(head -1 "$root/out") | $(cat "$root/err")" \
    "0 Usage: scripts/lane.sh up <name> <commit> | "
cp "$root/out" "$root/help-direct"
mkdir -p "$root/link"
ln -s "$primary/scripts/lane.sh" "$root/link/lane.sh"
"$root/link/lane.sh" --help >"$root/out" 2>"$root/err"
expect "--help through a symlink to lane.sh exits 0 and prints the same usage" \
    "$? $(cmp -s "$root/out" "$root/help-direct" && echo same) | $(cat "$root/err")" "0 same | "

touch "$root/case-probe"
if [ -e "$root/CASE-PROBE" ]; then
    lane up A "$c1"
    expect "on a disk that ignores case, up of a name that differs from lane a only by case exits 2 and names lane a" \
        "$status $(cat "$root/err") | $(ls "$lanes" | tr '\n' ' ')" \
        "2 lane.sh: $lanes/A is the directory a, because this disk ignores case; pick a name that differs by more than case | a b p "
    lane down A
    expect "down of that name leaves lane a and says why" \
        "$status $(tail -1 "$root/err") | $(git -C "$lanes/a" rev-parse HEAD)" \
        "0 lane.sh: left $lanes/A alone: it is the directory a, because this disk ignores case | $c1"
else
    lane up A "$c1"
    expect "on a case-sensitive disk, lane A beside lane a is a lane of its own" "$status $(ls "$lanes" | LC_ALL=C sort | tr '\n' ' ')" "0 A a b p "
    lane down A
fi

zsh_out=$(cd "$primary" && zsh -fc 'env=$(scripts/lane.sh env a) && eval "$env" && print -r -- "${SIM-no SIM}|$LANE_WORKTREE|$VERIFY_EVIDENCE" && cat "$LANE_WORKTREE/Secrets.xcconfig"' 2>&1)
expect "zsh evals env on a checkout path with a space in it" "$zsh_out" \
    "no SIM|$lanes/a|$evidence/detached-a
CLIENT_ID = test"

lane env nope
expect "env of a lane that does not exist exits 1" "$status $(cat "$root/err")" \
    "1 lane.sh: no lane nope; run lane.sh up nope <commit>"

lane assess a 3
expect "assess keeps a lane made today" "$status $(cat "$root/out")" "0 keep	active 0d ago, threshold 3d"
lane down --if-idle 3 a
expect "down --if-idle skips an active lane with exit 1" "$status $(cat "$root/err") | $([ -d "$lanes/a" ] && echo kept)" \
    "1 SKIPPED: active 0d ago, threshold 3d | kept"

(cd "$lanes/a/scripts" && exec sleep 60) &
sleeper=$!
sleep 0.5
lane assess a 0
kill "$sleeper"
wait "$sleeper" 2>/dev/null
expect "assess keeps a lane a process works in" "$(cat "$root/out")" "keep	in use by pid $sleeper (sleep)"

lane assess a 0
expect "assess removes a clean lane past the threshold" "$(cat "$root/out")" "remove	idle 0d"
env -u HOME "$primary/scripts/lane.sh" assess a 0 >"$root/out" 2>"$root/err"
expect "assess with HOME unset, as env -i leaves it, still reads DerivedData" "$? $(cat "$root/out" "$root/err")" "0 remove	idle 0d"

"$lanes/a/scripts/lane.sh" down a >"$root/out" 2>"$root/err"
expect "down from the lane's own copy of lane.sh exits 2" "$? $(cat "$root/err")" \
    "2 lane.sh: this copy of lane.sh lives in lane a; run $primary/scripts/lane.sh down a"

lane up lane-a "$c1"
wt="$lanes/lane-a"
echo lane-work >"$wt/lane.txt"
git -C "$wt" add lane.txt
git -C "$wt" commit -qm "lane work"
lane_sha=$(git -C "$wt" rev-parse HEAD)
printf '\003\004\005edited\n' >"$wt/app.bin"
cp "$wt/app.bin" "$root/app.bin.edited"
echo notes >"$wt/notes.txt"
mkdir -p "$wt/.claude/work" "$wt/.build/test-sim" "$wt/.build/verify"
echo plan >"$wt/.claude/work/note.md"
echo 'test-sim: exit=0' >"$wt/.build/test-sim/20261012-000000-test.log"
echo shot >"$wt/.build/verify/shot.txt"
for d in WorkoutTracker-aaa:lane-a WorkoutTracker-bbb:lane-a2; do
    mkdir -p "$dd/${d%%:*}"
    python3 -c 'import plistlib, sys
plistlib.dump({"WorkspacePath": sys.argv[2]}, open(sys.argv[1], "wb"))' "$dd/${d%%:*}/info.plist" "$lanes/${d#*:}/WorkoutTracker.xcodeproj"
done

lane assess lane-a 0
expect "assess keeps a lane with uncommitted changes" "$(cat "$root/out")" "keep	uncommitted changes (2)"

lane down lane-a
expect "down asks neither simctl nor Simlock anything, so it deletes no simulator" "$status $(sim_calls)" "0 "
saved=$(ls -d "$evidence/detached-lane-a"/down-* 2>/dev/null | head -1)
expect "down saves the head, the diff, untracked and work files, the commit, and the run evidence" \
    "$status $(ls "$saved" | tr '\n' ' ')| $(cat "$saved/head.txt") | $(tar -tf "$saved/untracked.tar" | grep -v '/$' | sort | tr '\n' ' ')| $(cat "$saved/test-sim/20261012-000000-test.log") $(cat "$saved/verify/shot.txt")" \
    "0 commits.bundle head.txt test-sim uncommitted.diff untracked.tar verify | $lane_sha lane work | .claude/work/note.md notes.txt | test-sim: exit=0 shot"
expect "the bundle verifies and holds the commit no ref held" \
    "$(git -C "$primary" bundle verify "$saved/commits.bundle" >/dev/null 2>&1 && echo verified) $(git -C "$primary" bundle list-heads "$saved/commits.bundle")" \
    "verified $lane_sha HEAD"
git -C "$primary" worktree add -q --detach "$root/restore" "$c1" 2>/dev/null
git -C "$root/restore" fetch -q "$saved/commits.bundle" HEAD
git -C "$root/restore" checkout -q FETCH_HEAD
git -C "$root/restore" apply "$saved/uncommitted.diff"
expect "the commit and the binary edit restore from what down saved" \
    "$(cat "$root/restore/lane.txt") $(cmp -s "$root/restore/app.bin" "$root/app.bin.edited" && echo same-bytes)" \
    "lane-work same-bytes"
git -C "$primary" worktree remove --force "$root/restore"
expect "down removes the worktree and its DerivedData but not lane-a2's" \
    "$([ -e "$wt" ] && echo worktree) $(git -C "$primary" worktree list | grep -c "lane-a") | $(ls "$dd")" \
    " 0 | WorkoutTracker-bbb"

lane down lane-a
expect "a second down exits 0 and says nothing" "$status $(cat "$root/err")" "0 "

GIT_FDS_LOG="$root/git-fds" lane up fds "$c1"
expect "up runs git with neither the lane lock (fd 5) nor sim-lock.sh's copy of stderr (fd 6)" \
    "$status $(cat "$root/git-fds" 2>/dev/null)" "0 "
lane down fds

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
