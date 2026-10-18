#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/prune-merged-worktrees-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/prune-merged-worktrees-harness.sh"

say
say "=== lanes: detached worktrees under .claude/worktrees ==="
lane_repo="$root/lane repo"
lanes="$lane_repo/.claude/worktrees"
P=PRUNE$$
mkdir -p "$root/lanebin" "$root/home" "$lane_repo/scripts" "$lane_repo/.githooks" "$lane_repo/.claude"
echo '{}' >"$lane_repo/.claude/settings.json"
cp "$script_dir/fake-xcrun" "$root/lanebin/xcrun"
printf '#!/usr/bin/env bash\necho "[]"\n' >"$root/lanebin/gh"
chmod +x "$root/lanebin/gh"
export FAKE_SIM_PREFIX=$P FAKE_SIM_STORE="$root/sims.json" FAKE_SIM_CALLS="$root/sim-calls"
export WORKOUT_HOST_LOCK_DIR="$root/locks" HOME="$root/home"
export WORKOUT_MEM_FLOOR=0
unset WORKOUT_SIM_CAP WORKOUT_ADMIT_WAIT WORKOUT_BUILD_SLOTS WORKOUT_LEASE_MINUTES
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
trap 'rm -rf "$root" /tmp/workout-verify-"$P"-*' EXIT
lane_path="$root/lanebin:$PATH"
git -C "$root" init --bare --quiet lane-origin.git
git -C "$lane_repo" init -q -b main
git -C "$lane_repo" remote add origin "$root/lane-origin.git"
cp "$script_dir/../../.gitignore" "$lane_repo/"
cp "$script_dir/../../.githooks/post-checkout" "$lane_repo/.githooks/"
for s in lane.sh lane-help.sh sim-pool.sh sim-lock.sh ensure-simulator.sh sim-keyboard.sh bootstrap-xcode-worktree.sh; do
    cp "$script_dir/../$s" "$lane_repo/scripts/"
done
GIT_COMMITTER_DATE=2020-01-01T00:00:00 GIT_AUTHOR_DATE=2020-01-01T00:00:00 \
    git -C "$lane_repo" add -A
GIT_COMMITTER_DATE=2020-01-01T00:00:00 GIT_AUTHOR_DATE=2020-01-01T00:00:00 \
    git -C "$lane_repo" commit -qm old
old_sha=$(git -C "$lane_repo" rev-parse HEAD)
echo base >"$lane_repo/base.txt"
git -C "$lane_repo" add -A
git -C "$lane_repo" commit -qm base
git -C "$lane_repo" push -q -u origin main

up() { PATH="$lane_path" "$lane_repo/scripts/lane.sh" up "$1" "${2:-main}" >/dev/null 2>"$root/up.err" || cat "$root/up.err"; }
age_days() {
    python3 -c 'import os, sys, time
t = time.time() - float(sys.argv[1]) * 86400
for p in sys.argv[2:]: os.utime(p, (t, t))' "$@"
}
idle() {
    local admin
    admin=$(git -C "$lanes/$1" rev-parse --absolute-git-dir)
    age_days 5 "$admin/logs/HEAD" "$admin/HEAD" "$lane_repo/.claude/work/evidence/detached-$1"
}
for l in aaa-idle zzz-raced recent dirty unref work; do up "$l"; done
up oldsha "$old_sha"
for l in aaa-idle zzz-raced recent dirty unref work; do idle "$l"; done
mkdir -p "$lanes/recent/.build/test-sim"
echo 'test-sim: exit=0' >"$lanes/recent/.build/test-sim/20261011-000000-test.log"
age_days 1 "$lanes/recent/.build/test-sim/20261011-000000-test.log" "$lanes/recent/.build/test-sim"
age_days 5 "$lanes/recent/.build"
echo edited >>"$lanes/dirty/base.txt"
echo mine >"$lanes/unref/mine.txt"
git -C "$lanes/unref" add -A
git -C "$lanes/unref" commit -qm mine
idle unref
up reup
echo again >"$lanes/reup/again.txt"
git -C "$lanes/reup" add -A
git -C "$lanes/reup" commit -qm again
up reup "$(git -C "$lanes/reup" rev-parse HEAD)"
idle reup
mkdir -p "$lanes/work/.claude/work"
echo plan >"$lanes/work/.claude/work/plan.md"
git -C "$lane_repo" worktree add -q --detach "$root/outside" main
git -C "$lane_repo" worktree add -q --detach "$lanes/not a lane" main

PATH="$lane_path" "$prune" --repo "$lane_repo" --no-size >"$root/out.txt" 2>"$root/err.txt"
lanes_status=$?
cat "$root/out.txt"
row_for() { awk -v w="$lanes/$2" '/^'"$1"'$/{f=1;next} /^[A-Z]+$/{f=0} f && index($0, "  " w) == length($0) - length(w) - 1'  "$root/out.txt"; }
assert_lane() {
    local line
    line=$(row_for "$1" "$2")
    if [ -z "$line" ]; then
        bad "lane $2 missing from $1"
    elif [ "$3" = - ]; then
        ok "lane $2 is a candidate"
    elif printf '%s' "$line" | grep -qF -- "  $3  "; then
        ok "lane $2 kept: $3"
    else
        bad "lane $2 in $1 with the wrong reason: $line"
    fi
}
if [ "$lanes_status" -eq 0 ]; then ok "lane dry run exits 0"; else bad "lane dry run exited $lanes_status"; cat "$root/err.txt"; fi
assert_lane CANDIDATES aaa-idle -
assert_lane CANDIDATES zzz-raced -
assert_lane KEPT recent "lane active 1d ago, threshold 3d"
assert_lane KEPT dirty "lane uncommitted changes (1)"
assert_lane KEPT unref "lane commits no branch or tag holds (1)"
assert_lane KEPT reup "lane commits no branch or tag holds (1)"
assert_lane CANDIDATES work -
assert_lane KEPT oldsha "lane active 0d ago, threshold 3d"
assert_lane KEPT "not a lane" "detached under .claude/worktrees, but 'not a lane' is not a lane name; remove it by hand"
if kept | grep -F "$root/outside" | grep -qF "detached HEAD: no branch resolves to a PR"; then
    ok "a detached worktree outside .claude/worktrees keeps today's reason"
else
    bad "the detached worktree outside .claude/worktrees lost today's reason"
fi

say
say "=== lanes --apply, with a commit landing in zzz-raced mid-apply ==="
cat >"$root/lanebin/git" <<'WRAP'
#!/usr/bin/env bash
case " $* " in
    *" worktree remove "*)
        if [ ! -f "$RACE_FLAG" ]; then
            : >"$RACE_FLAG"
            echo raced >"$RACE_TARGET/raced.txt"
            "$REAL_GIT" -C "$RACE_TARGET" add -A
            "$REAL_GIT" -C "$RACE_TARGET" commit -qm "landed mid-apply"
        fi ;;
esac
exec "$REAL_GIT" "$@"
WRAP
chmod +x "$root/lanebin/git"
REAL_GIT=$(command -v git) RACE_TARGET="$lanes/zzz-raced" RACE_FLAG="$root/lane-raced.flag" PATH="$lane_path" \
    "$prune" --repo "$lane_repo" --no-size --apply >"$root/lane-apply.txt" 2>&1
lane_apply_status=$?
rm -f "$root/lanebin/git"
cat "$root/lane-apply.txt"
devices=$(PATH="$lane_path" "$lane_repo/scripts/sim-pool.sh" list | awk -F '\t' '$3 == "lane" { print $4 }' | tr '\n' ' ')
if [ ! -e "$lanes/aaa-idle" ] && [ -f "$lane_repo/.claude/work/evidence/detached-aaa-idle"/down-*/head.txt ]; then
    ok "--apply removed the idle lane after saving its head"
else
    bad "--apply did not remove aaa-idle, or saved nothing"
fi
if [ "$(tar -tf "$lane_repo/.claude/work/evidence/detached-work"/down-*/untracked.tar 2>&1 | tr "\n" " ")" = ".claude/work/ .claude/work/plan.md " ]; then
    ok "--apply removed the idle lane holding only an ignored note, after saving the note"
else
    bad "--apply did not save the ignored note of lane work"
fi
if [ "$devices" = "workout-lane-dirty workout-lane-oldsha workout-lane-recent workout-lane-reup workout-lane-unref workout-lane-zzz-raced " ]; then
    ok "--apply deleted the idle lanes' simulators and no other"
else
    bad "lane simulators after --apply: $devices"
fi
if grep -qxF "  SKIPPED: commits no branch or tag holds (1)" "$root/lane-apply.txt" && [ -f "$lanes/zzz-raced/raced.txt" ]; then
    ok "a lane whose HEAD moved after the scan is SKIPPED and survives"
else
    bad "the raced lane was not skipped"
fi
if [ "$lane_apply_status" -eq 1 ]; then ok "a skipped lane makes --apply exit 1"; else bad "--apply exited $lane_apply_status"; fi
for l in recent dirty unref oldsha reup; do
    [ -d "$lanes/$l" ] || bad "--apply removed the kept lane $l"
done

say
say "passed $pass, failed $fail"
[ "$fail" -eq 0 ] || exit 1
