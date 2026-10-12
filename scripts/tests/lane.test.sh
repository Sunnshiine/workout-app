#!/bin/bash
set -uo pipefail

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
P=LANE$$
holder=
cleanup() {
    [ -z "$holder" ] || kill "$holder" 2>/dev/null
    rm -rf "$root" /tmp/workout-verify-"$P"-*
}
trap cleanup EXIT
primary="$root/primary repo"
lanes="$primary/.claude/worktrees"
evidence="$primary/.claude/work/evidence"
mkdir -p "$root/bin" "$root/home" "$primary"
cp "$scripts/tests/fake-xcrun" "$root/bin/xcrun"
export PATH="$root/bin:$PATH" HOME="$root/home" WORKOUT_HOST_LOCK_DIR="$root/locks"
export FAKE_SIM_PREFIX=$P FAKE_SIM_STORE="$root/store.json" FAKE_SIM_CALLS="$root/calls"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

g() { git -C "$primary" "$@" >/dev/null 2>&1; }
lane() {
    rm -f "$root/calls"
    "$primary/scripts/lane.sh" "$@" >"$root/out" 2>"$root/err"
    status=$?
}
calls() { cat "$root/calls" 2>/dev/null; }
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}
env_lines() {
    printf "export SIM='%s'\nexport LANE_WORKTREE='%s'\nexport VERIFY_EVIDENCE='%s'" "$1" "$lanes/$2" "$evidence/detached-$2"
}
lane_rows() { "$primary/scripts/sim-pool.sh" list | awk -F '\t' '$3 == "lane" { print $1, $4 }'; }
hold() {
    mkdir -p "$(dirname "$1")"
    python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a")
fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[1], "w").write(sys.argv[2] + "\n")
open(sys.argv[3], "w").close()
time.sleep(120)' "$1" "$2" "$root/held" &
    holder=$!
    while [ ! -f "$root/held" ]; do sleep 0.05; done
    rm -f "$root/held"
}
release() { kill "$holder"; wait "$holder" 2>/dev/null; holder=; }

git init -q --bare "$root/origin.git"
g init -b main
g remote add origin "$root/origin.git"
mkdir -p "$primary/scripts" "$primary/.githooks"
cp "$scripts/../.gitignore" "$primary/.gitignore"
cp "$scripts/../.githooks/post-checkout" "$primary/.githooks/"
for s in lane.sh sim-pool.sh sim-lock.sh ensure-simulator.sh sim-keyboard.sh bootstrap-xcode-worktree.sh; do
    cp "$scripts/$s" "$primary/scripts/"
done
printf '\000\001\002binary\n' >"$primary/app.bin"
g add -A
g commit -m first
c1=$(git -C "$primary" rev-parse HEAD)
echo two >"$primary/two.txt"
g add -A
g commit -m second
c2=$(git -C "$primary" rev-parse HEAD)
g push -u origin main
printf 'CLIENT_ID = test\n' >"$primary/Secrets.xcconfig"

git clone -q "$root/origin.git" "$root/other"
echo feature >"$root/other/feature.txt"
git -C "$root/other" add -A
git -C "$root/other" commit -qm feature
c3=$(git -C "$root/other" rev-parse HEAD)
git -C "$root/other" push -q origin HEAD:feature
echo pulled >"$root/other/pulled.txt"
git -C "$root/other" add -A
git -C "$root/other" commit -qm pulled
c4=$(git -C "$root/other" rev-parse HEAD)
git -C "$root/other" push -q origin HEAD:refs/pull/7/head

lane up a "${c1:0:8}"
expect "up prints the three export lines and leaves the lane's simulator Shutdown" \
    "$status $(cat "$root/out") | $(calls | tail -1) | $(lane_rows)" \
    "0 $(env_lines "$P-2" a) | clone $P-1 workout-lane-a | $P-2 workout-lane-a"
expect "the worktree is detached at the full SHA, with Secrets.xcconfig and the evidence dir" \
    "$(git -C "$lanes/a" rev-parse HEAD) $(git -C "$lanes/a" symbolic-ref -q HEAD || echo detached) $(cat "$lanes/a/Secrets.xcconfig") $([ -d "$evidence/detached-a" ] && echo evidence)" \
    "$c1 detached CLIENT_ID = test evidence"
first=$(cat "$root/out")

lane up a "$c1"
expect "a second up prints the same lines and creates nothing" "$status $(cat "$root/out") | $(calls)" "0 $first | "

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
expect "an unknown commit exits 2 and creates no worktree and no simulator" \
    "$status $(tail -1 "$root/err") | $(ls "$lanes") | $(lane_rows | grep -c workout-lane-u)" \
    "2 lane.sh: unknown commit deadbeef, even after fetching origin | a
b
p | 0"

lane up "x $c1"
expect "one argument holding a name and a SHA, as zsh passes \"x <sha>\", exits 2 and creates nothing" \
    "$status $(head -1 "$root/err") | $(ls "$lanes" | tr '\n' ' ')| $(calls)" \
    "2 Usage: scripts/lane.sh up <name> <commit> | a b p | "

zsh_out=$(cd "$primary" && zsh -fc 'env=$(scripts/lane.sh env a) && eval "$env" && print -r -- "$SIM|$LANE_WORKTREE|$VERIFY_EVIDENCE" && cat "$LANE_WORKTREE/Secrets.xcconfig"' 2>&1)
expect "zsh evals env on a checkout path with a space in it" "$zsh_out" \
    "$P-2|$lanes/a|$evidence/detached-a
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
expect "assess keeps a lane a process works in" "$(cat "$root/out")" "keep	in use by pid $sleeper"

lane assess a 0
expect "assess removes a clean lane past the threshold" "$(cat "$root/out")" "remove	idle 0d"
hold "/tmp/workout-verify-$P-2/lock" "verify.sh launch (pid 4244)"
lane assess a 0
release
expect "assess keeps a lane whose simulator a run holds" "$(cat "$root/out")" "keep	in use by verify.sh launch (pid 4244)"

"$lanes/a/scripts/lane.sh" down a >"$root/out" 2>"$root/err"
expect "down from the lane's own copy of lane.sh exits 2" "$? $(cat "$root/err")" \
    "2 lane.sh: this copy of lane.sh lives in lane a; run $primary/scripts/lane.sh down a"

lane up lane-a "$c1"
wt="$lanes/lane-a"
lane_udid=$(lane_rows | awk '$2 == "workout-lane-lane-a" { print $1 }')
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
dd="$HOME/Library/Developer/Xcode/DerivedData"
for d in WorkoutTracker-aaa:lane-a WorkoutTracker-bbb:lane-a2; do
    mkdir -p "$dd/${d%%:*}"
    python3 -c 'import plistlib, sys
plistlib.dump({"WorkspacePath": sys.argv[2]}, open(sys.argv[1], "wb"))' "$dd/${d%%:*}/info.plist" "$lanes/${d#*:}/WorkoutTracker.xcodeproj"
done

lane assess lane-a 0
expect "assess keeps a lane with uncommitted changes" "$(cat "$root/out")" "keep	uncommitted changes (2)"

hold "/tmp/workout-verify-$lane_udid/lock" "test-sim.sh unit (pid 4242)"
lane down lane-a
release
expect "down while a run holds the lane's simulator exits 75 and removes nothing" \
    "$status $(cat "$root/err") | $([ -d "$wt" ] && echo worktree) $(lane_rows | grep -c workout-lane-lane-a) $(ls "$dd" | tr '\n' ' ')" \
    "75 $lane_udid is held by a test-sim.sh unit (pid 4242); wait for it to finish, or use another simulator (lsof /tmp/workout-verify-$lane_udid/lock lists every process holding it) | worktree 1 WorkoutTracker-aaa WorkoutTracker-bbb "

lane down lane-a
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
expect "down removes the worktree, its DerivedData but not lane-a2's, and its simulator" \
    "$([ -e "$wt" ] && echo worktree) $(git -C "$primary" worktree list | grep -c "lane-a") | $(ls "$dd") | $(lane_rows | grep -c workout-lane-lane-a)" \
    " 0 | WorkoutTracker-bbb | 0"

lane down lane-a
expect "a second down exits 0" "$status $(cat "$root/err")" \
    "0 sim-pool: no device is named workout-lane-lane-a; nothing to delete"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
