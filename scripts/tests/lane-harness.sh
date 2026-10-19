# shellcheck shell=bash
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
real_git=$(type -P git)
cat >"$root/bin/git" <<STUB
#!/bin/bash
if [ -n "\${GIT_FDS_LOG:-}" ]; then
    for fd in 5 6; do { true >&\$fd; } 2>/dev/null && echo "git \$1 holds fd \$fd" >>"\$GIT_FDS_LOG"; done
fi
exec "$real_git" "\$@"
STUB
chmod +x "$root/bin/git"
export PATH="$root/bin:/usr/bin:/bin" HOME="$root/home" WORKOUT_HOST_LOCK_DIR="$root/locks"
export WORKOUT_MEM_FLOOR=0 WORKOUT_DEP_STORE="$root/dep-store"
unset WORKOUT_SIM_CAP WORKOUT_ADMIT_WAIT WORKOUT_BUILD_SLOTS WORKOUT_LEASE_MINUTES
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
for s in lane.sh lane-help.sh sim-pool.sh sim-lock.sh ensure-simulator.sh sim-keyboard.sh bootstrap-xcode-worktree.sh dep-store.sh; do
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
dd="$HOME/Library/Developer/Xcode/DerivedData"
