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
mkdir -p "$primary/.claude"
echo '{}' >"$primary/.claude/settings.json"
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

"$primary/scripts/lane.sh" --help >"$root/out" 2>"$root/err"
expect "--help prints the usage on stdout and exits 0" "$? $(head -1 "$root/out") | $(cat "$root/err")" \
    "0 Usage: scripts/lane.sh up <name> <commit> | "

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
expect "assess keeps a lane a process works in" "$(cat "$root/out")" "keep	in use by pid $sleeper (sleep)"

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

python3 -c 'import time; time.sleep(60)' -UITEST_FIXTURE &
fixture=$!
echo "$fixture" >"/tmp/workout-verify-$lane_udid/pid"
lane down lane-a
kill "$fixture"
wait "$fixture" 2>/dev/null
rm -f "/tmp/workout-verify-$lane_udid/pid"
expect "down while a verify run's app is live exits 75 before it saves or removes anything" \
    "$status $(cat "$root/err") | $([ -d "$wt" ] && echo worktree) $(ls "$evidence/detached-lane-a" | grep -c down-) $(lane_rows | grep -c workout-lane-lane-a) $(ls "$dd" | tr '\n' ' ')" \
    "75 sim-pool: a verify run owns the app on $lane_udid (pid $fixture); if it is yours, run: SIM=$lane_udid $primary/.agents/skills/verify/verify.sh stop, and delete again | worktree 0 1 WorkoutTracker-aaa WorkoutTracker-bbb "

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

commit_in() {
    echo "$2" >"$lanes/$1/$2.txt"
    git -C "$lanes/$1" add "$2.txt"
    git -C "$lanes/$1" commit -qm "$2"
    git -C "$lanes/$1" rev-parse HEAD
}

lane up reup "$c1"
reup_sha=$(commit_in reup unsaved)
lane up reup "$reup_sha"
up_result="$status $(git -C "$lanes/reup" rev-parse refs/worktree/lane-base)"
lane assess reup 0
expect "up at the lane's own new commit keeps the lane's base, so assess keeps that commit" \
    "$up_result | $(cat "$root/out")" "0 $c1 | keep	commits no branch or tag holds (1)"
lane down reup
saved=$(ls -d "$evidence/detached-reup"/down-* 2>/dev/null | head -1)
expect "down then bundles that commit" "$status $(git -C "$primary" bundle list-heads "$saved/commits.bundle" 2>&1)" \
    "0 $reup_sha HEAD"

lane up results "$c1"
results=$(grep -rhoE --include='*.sh' --exclude-dir=tests '\.build/[A-Za-z0-9_-]+' "$scripts" "$scripts/../.agents" \
    | sed 's|^\.build/||' | grep -vx debug | sort -u | tr '\n' ' ')
for d in $results debug; do
    mkdir -p "$lanes/results/.build/$d"
    echo "$d" >"$lanes/results/.build/$d/result.txt"
done
mkdir -p "$lanes/results/.build/verify/node_modules/xcodebuildmcp"
echo driver >"$lanes/results/.build/verify/node_modules/xcodebuildmcp/axe"
echo dotfile >"$lanes/results/.build/verify/.state"
mkdir -p "$lanes/results/.workout-cli"
echo logged >"$lanes/results/.workout-cli/workbook.json"
lane down results
saved=$(ls -d "$evidence/detached-results"/down-* 2>/dev/null | head -1)
expect "down saves every results dir under .build the repo's scripts write, and the CLI's home, but no build products" \
    "$status $results| $(cd "$saved" && find . -type f ! -name head.txt ! -name untracked.tar | sort | tr '\n' ' ')| $(tar -tf "$saved/untracked.tar" | grep -v '/$')" \
    "0 crap flake-hunt test-sim verify | ./crap/result.txt ./flake-hunt/result.txt ./test-sim/result.txt ./verify/.state ./verify/result.txt | .workout-cli/workbook.json"

lane up staged "$c1"
echo staged >"$lanes/staged/staged.txt"
git -C "$lanes/staged" add staged.txt
rm "$lanes/staged/staged.txt"
lane assess staged 0
assessed=$(cat "$root/out")
lane down staged
saved=$(ls -d "$evidence/detached-staged"/down-* 2>/dev/null | head -1)
git -C "$primary" worktree add -q --detach "$root/restore" "$c1" 2>/dev/null
git -C "$root/restore" apply --cached "$saved/staged.diff"
expect "down saves a new file staged and then deleted from the tree, and it restores into the index" \
    "$assessed | $status $(git -C "$root/restore" show :staged.txt 2>&1)" "keep	uncommitted changes (1) | 0 staged"
git -C "$primary" worktree remove --force "$root/restore"

lane up back "$c1"
back_sha=$(commit_in back left-behind)
git -C "$lanes/back" checkout -q "$c1"
lane assess back 0
expect "assess keeps a lane whose commit only its reflog holds, after a checkout back to its base" \
    "$(cat "$root/out")" "keep	commits no branch or tag holds (1)"
lane down back
saved=$(ls -d "$evidence/detached-back"/down-* 2>/dev/null | head -1)
expect "down bundles a commit only the lane's reflog holds" \
    "$status $(git -C "$primary" bundle list-heads "$saved/commits.bundle" 2>&1)" \
    "0 $back_sha refs/worktree/lane-save/$back_sha"

lane up gone "$c1"
gone_sha=$(commit_in gone pushed-then-deleted)
git -C "$lanes/gone" push -q origin HEAD:refs/heads/gone 2>/dev/null
git -C "$root/origin.git" branch -q -D gone
lane assess gone 0
expect "assess keeps a lane whose pushed branch the server deleted, while a stale remote-tracking ref names it" \
    "$(cat "$root/out")" "keep	commits no branch or tag holds (1)"
g fetch --prune origin
lane assess gone 0
expect "assess keeps that lane after fetch --prune" "$(cat "$root/out")" "keep	commits no branch or tag holds (1)"
lane down gone
saved=$(ls -d "$evidence/detached-gone"/down-* 2>/dev/null | head -1)
expect "down bundles the commit the deleted branch held" \
    "$status $(git -C "$primary" bundle list-heads "$saved/commits.bundle" 2>&1)" "0 $gone_sha HEAD"

lane up busy "$c1"
(cd "$lanes/busy" && exec sleep 60) &
sleeper=$!
sleep 0.5
lane down busy
kill "$sleeper"
wait "$sleeper" 2>/dev/null
expect "down while another process works in the lane exits 75 and removes nothing" \
    "$status $(cat "$root/err") | $([ -d "$lanes/busy" ] && echo worktree) $(lane_rows | grep -c workout-lane-busy)" \
    "75 lane.sh: pid $sleeper (sleep) works in $lanes/busy; stop it or cd out | worktree 1"
(cd "$lanes/busy" && "$primary/scripts/lane.sh" down busy >"$root/out" 2>"$root/err")
expect "down run from a shell inside the lane removes it" "$? $([ -d "$lanes/busy" ] && echo worktree)" "0 "

crash_add() {
    lane up "$1" "$c1"
    echo initializing >"$(git -C "$lanes/$1" rev-parse --absolute-git-dir)/locked"
}
locked() { git -C "$primary" worktree list --porcelain | grep -c "^locked" || true; }
crash_add crashed
lane assess crashed 0
expect "assess keeps a lane a crashed git worktree add left, and says how to repair it" \
    "$(cat "$root/out")" "keep	a git worktree add crashed here; lane.sh up or down repairs it"
lane up crashed "$c1"
expect "up repairs a lane a crashed git worktree add left" \
    "$status $(locked) $(git -C "$lanes/crashed" rev-parse HEAD)" "0 0 $c1"
crash_add crashed2
lane down crashed2
expect "down saves and removes a lane a crashed git worktree add left" \
    "$status $([ -d "$lanes/crashed2" ] && echo worktree) $(ls "$evidence/detached-crashed2" | grep -c down-) $(locked)" "0  1 0"
lane down crashed

lane up ign "$c1"
mkdir -p "$lanes/ign/.claude"
echo profile >"$lanes/ign/default.profraw"
echo '{}' >"$lanes/ign/.claude/settings.local.json"
lane assess ign 0
expect "assess removes a clean lane whose only ignored files a build or a session regenerates" \
    "$(cat "$root/out")" "remove	idle 0d"
odd=$(printf "it's\there.txt")
echo odd >"$lanes/ign/$odd"
lane down ign
saved=$(ls -d "$evidence/detached-ign"/down-* 2>/dev/null | head -1)
mkdir "$root/ign-restore"
tar -xf "$saved/untracked.tar" -C "$root/ign-restore"
expect "down saves a file whose name holds a quote and a tab, and leaves out regenerable files" \
    "$status $(ls -A "$root/ign-restore") $(cat "$root/ign-restore/$odd")" "0 $odd odd"

g worktree add --detach "$root/moved-away" main
mv "$root/moved-away" "$root/moved-here"
lane up m "$c1"
up_status=$status
lane down m
expect "up and down leave another worktree's stale record alone" \
    "$up_status $status $(git -C "$primary" worktree list --porcelain | grep -c -e "^worktree $root/moved-away$" -e "^worktree $lanes/m$")" \
    "0 0 1"

lane up moved "$c1"
moved_sha=$(commit_in moved moved-work)
mv "$lanes/moved" "$root/moved-lane"
missing="lane.sh: $lanes/moved is registered but missing; if you moved it, run git worktree repair <new path>; to discard it and anything only it holds, git worktree remove --force $lanes/moved"
lane down moved
down_result="$status $(cat "$root/err")"
lane up moved "$c1"
expect "down and up refuse a lane whose directory moved, and say how to repair or discard it" \
    "$down_result | $status $(cat "$root/err")" "2 $missing | 2 $missing"
git -C "$primary" worktree repair "$root/moved-lane" 2>/dev/null
expect "the moved lane's commit survives, and git worktree repair brings it back" \
    "$(git -C "$root/moved-lane" rev-parse HEAD 2>&1) $(git -C "$primary" worktree list --porcelain | grep -c "^worktree $root/moved-lane$")" \
    "$moved_sha 1"
git -C "$primary" worktree remove --force "$root/moved-lane"

g worktree add -b feature "$lanes/feature" main
lane down feature
expect "down refuses a worktree on a branch with exit 2 and leaves it" \
    "$status $(cat "$root/err") | $([ -d "$lanes/feature" ] && echo kept)" \
    "2 lane.sh: $lanes/feature is on branch feature, not a lane; prune-merged-worktrees.sh decides branch worktrees | kept"

bundle_subjects() {
    rm -rf "$root/unbundled"
    git clone -q "$root/origin.git" "$root/unbundled"
    git -C "$root/unbundled" fetch -q "$1" HEAD 2>&1 && git -C "$root/unbundled" log --format=%s "$c2..FETCH_HEAD" | tr '\n' ' '
}

aged="@$(($(date +%s) - 100 * 86400)) +0000"
for n in aged foreign; do
    GIT_COMMITTER_DATE=$aged lane up "$n" "$c2"
    GIT_COMMITTER_DATE=$aged commit_in "$n" dated-a >/dev/null
    commit_in "$n" dated-b >/dev/null
done
git -C "$lanes/foreign" update-ref -d refs/worktree/lane-base
git -C "$primary" reflog expire --expire=90.days --all
for n in aged foreign; do
    lane assess "$n" 0
    expect "assess keeps both commits of a $n lane after reflog expiry dropped its creation entry" \
        "$(head -1 "$(git -C "$lanes/$n" rev-parse --absolute-git-dir)/logs/HEAD" | cut -c1-40) $(cat "$root/out")" \
        "$(git -C "$lanes/$n" rev-parse HEAD~1) keep	commits no branch or tag holds (2)"
    lane down "$n"
    expect "down bundles both commits of a $n lane after reflog expiry dropped its creation entry" \
        "$status $(bundle_subjects "$(ls -d "$evidence/detached-$n"/down-*)/commits.bundle")" "0 dated-b dated-a "
done

lane up nolog "$c2"
commit_in nolog no-reflog >/dev/null
git -C "$lanes/nolog" reflog expire --expire=now --expire-unreachable=now --all
lane assess nolog 0
expect "assess keeps the commit of a lane whose reflog is entirely expired" \
    "$(wc -c <"$(git -C "$lanes/nolog" rev-parse --absolute-git-dir)/logs/HEAD" | tr -d ' ') $(cat "$root/out")" \
    "0 keep	commits no branch or tag holds (1)"
lane down nolog
expect "down bundles the commit of a lane whose reflog is entirely expired, and removes it" \
    "$status $(bundle_subjects "$(ls -d "$evidence/detached-nolog"/down-*)/commits.bundle")| $([ -d "$lanes/nolog" ] && echo worktree)" \
    "0 no-reflog | "

common="$primary/.git"
printf 'two.txt filter=slow\n' >"$common/info/attributes"
g config filter.slow.smudge 'sleep 2; cat'
"$primary/scripts/lane.sh" up z "$c2" >"$root/z1.out" 2>"$root/z1.err" &
first_up=$!
for _ in $(seq 100); do [ -f "$common/worktrees/z/locked" ] && break; sleep 0.05; done
lane up z "$c2"
second=$status
wait "$first_up"
first=$?
rm "$common/info/attributes"
g config --unset filter.slow.smudge
expect "a second up of a lane waits out the first's slow checkout, prints the same lines, and repairs nothing" \
    "$first $second $(cat "$root/z1.out") | $(cat "$root/out") | $(git -C "$primary" worktree list --porcelain | grep -c "^worktree $lanes/z$") $(cat "$root/z1.err" "$root/err" | grep -c crashed)" \
    "0 0 $(env_lines "$(lane_rows | awk '$2 == "workout-lane-z" { print $1 }')" z) | $(env_lines "$(lane_rows | awk '$2 == "workout-lane-z" { print $1 }')" z) | 1 0"

hold "$root/locks/lane-z" "lane.sh down z (pid 4245)"
WORKOUT_ADMIT_WAIT=0 lane down z
release
expect "down of a lane another up or down holds exits 75 and names the holder" \
    "$status $(cat "$root/err") | $([ -d "$lanes/z" ] && echo worktree)" \
    "75 lane.sh: waited 0 s for lane z, held by lane.sh down z (pid 4245) (lsof $root/locks/lane-z lists it) | worktree"

printf '#!/bin/sh\n(cd / && exec sleep 30) >/dev/null 2>&1 &\necho $! >"%s"\n' "$root/daemon.pid" >"$common/hooks/post-checkout"
chmod +x "$common/hooks/post-checkout"
lane up daemon "$c2"
rm "$common/hooks/post-checkout"
WORKOUT_ADMIT_WAIT=0 lane down daemon
kill "$(cat "$root/daemon.pid")"
expect "a process git leaves running after up does not hold the lane's lock" "$status $([ -d "$lanes/daemon" ] && echo worktree)" "0 "

lane up booted "$c1"
booted_udid=$(lane_rows | awk '$2 == "workout-lane-booted" { print $1 }')
xcrun simctl boot "$booted_udid"
lane assess booted 0
xcrun simctl shutdown "$booted_udid"
expect "assess keeps a lane whose simulator is booted" "$(cat "$root/out")" "keep	simulator $booted_udid is booted"
lane down booted

lane up quiet "$c1"
ten_days_ago=$(date -v-10d +%Y%m%d%H%M)
quiet_admin=$(git -C "$lanes/quiet" rev-parse --absolute-git-dir)
touch -t "$ten_days_ago" "$quiet_admin/logs/HEAD" "$quiet_admin/HEAD" "$evidence/detached-quiet"
lane assess quiet 3
idle_before=$(cat "$root/out")
mkdir -p "$dd/WorkoutTracker-quiet/Build"
python3 -c 'import plistlib, sys
plistlib.dump({"WorkspacePath": sys.argv[2]}, open(sys.argv[1], "wb"))' "$dd/WorkoutTracker-quiet/info.plist" "$lanes/quiet/WorkoutTracker.xcodeproj"
touch -t "$ten_days_ago" "$dd/WorkoutTracker-quiet" "$dd/WorkoutTracker-quiet/info.plist"
lane assess quiet 3
expect "assess keeps a lane idle for 10 days whose DerivedData a build touched today" \
    "$idle_before | $(cat "$root/out")" "remove	idle 10d | keep	active 0d ago, threshold 3d"
lane down quiet

crash_add stuck
(cd "$lanes/stuck" && exec sleep 60) &
sleeper=$!
sleep 0.5
lane down stuck
kill "$sleeper"
wait "$sleeper" 2>/dev/null
expect "down refusing a crashed add's lane leaves git's lock in place" \
    "$status $(cat "$root/err") | $(cat "$(git -C "$lanes/stuck" rev-parse --absolute-git-dir)/locked")" \
    "75 lane.sh: pid $sleeper (sleep) works in $lanes/stuck; stop it or cd out | initializing"
lane down stuck

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
