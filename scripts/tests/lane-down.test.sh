#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/lane-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/lane-harness.sh"

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
regenerable="debug scratch ci-visual-diffs"
results=$(grep -rhoE --include='*.sh' --exclude-dir=tests '\.build/[A-Za-z0-9_-]+' "$scripts" "$scripts/../.agents" \
    | sed 's|^\.build/||' | grep -vxF "$(printf '%s\n' $regenerable)" | sort -u | tr '\n' ' ')
for d in $results $regenerable; do
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
    "0 check-each-commit crap flake-hunt measure-host mutate test-sim verify | ./check-each-commit/result.txt ./crap/result.txt ./flake-hunt/result.txt ./measure-host/result.txt ./mutate/result.txt ./test-sim/result.txt ./verify/.state ./verify/result.txt | .workout-cli/workbook.json"

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

xcode=$root/Xcode.app/Contents/Developer
mkdir -p "$xcode/usr/bin"
cp /bin/sleep "$xcode/usr/bin/ibtoold" && codesign -s - -f "$xcode/usr/bin/ibtoold" 2>/dev/null
printf '#!/bin/sh\necho %s\n' "$xcode" >"$root/bin/xcode-select"
chmod +x "$root/bin/xcode-select"
lane up helper "$c1"
(cd "$lanes/helper" && exec "$xcode/usr/bin/ibtoold" 60 & echo $! >"$root/helper.pid")
sleep 0.5
lane down helper
kill "$(cat "$root/helper.pid")"
expect "down removes a lane that only an Xcode helper orphaned to launchd works in, as ibtoold after a build" \
    "$status $([ -d "$lanes/helper" ] && echo worktree)" "0 "
lane up tool "$c1"
(cd "$lanes/tool" && exec "$xcode/usr/bin/ibtoold" 60) &
tool=$!
sleep 0.5
lane down tool
kill "$tool"
wait "$tool" 2>/dev/null
expect "an Xcode tool an agent runs in the lane still holds it" "$status $(cat "$root/err")" \
    "75 lane.sh: pid $tool (ibtoold) works in $lanes/tool; stop it or cd out"
lane down tool
rm "$root/bin/xcode-select"

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

lane up stored "$c1"
mkdir -p "$root/payload/checkouts/pkg" "$dd/WorkoutTracker-stored"
echo 'let x = 1' >"$root/payload/checkouts/pkg/x.swift"
# shellcheck disable=SC2016  # sh -c expands them
"$scripts/dep-store.sh" publish k1 sh -c 'cp -R "$0"/. "$DEP_STORE_OUT"' "$root/payload" 2>/dev/null
python3 -c 'import plistlib, sys
plistlib.dump({"WorkspacePath": sys.argv[2]}, open(sys.argv[1], "wb"))' "$dd/WorkoutTracker-stored/info.plist" "$lanes/stored/WorkoutTracker.xcodeproj"
"$scripts/dep-store.sh" clone k1 "$dd/WorkoutTracker-stored/SourcePackages"
sleep 60 &
producer=$!
mkdir -p "$WORKOUT_DEP_STORE/staging/$producer.k2.aaaaaa" "$WORKOUT_DEP_STORE/staging/999999.k3.bbbbbb"
entry_sums() { (cd "$WORKOUT_DEP_STORE/entries" && find . -type f ! -name used | sort | xargs shasum); }
before=$(entry_sums)
lane down stored
kill "$producer"
wait "$producer" 2>/dev/null
expect "down removes the lane's DerivedData and prunes the store, which keeps the entry the lane cloned and a live producer's staging dir" \
    "$status $([ -e "$dd/WorkoutTracker-stored" ] && echo dd) | $([ "$(entry_sums)" = "$before" ] && echo entry-whole) | $(ls "$WORKOUT_DEP_STORE/staging")" \
    "0  | entry-whole | $producer.k2.aaaaaa"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
