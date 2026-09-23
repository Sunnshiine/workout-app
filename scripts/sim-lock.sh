# shellcheck shell=bash
# Both scripts source this file, because the lock lives on the caller's fd 9 and a child process
# would release it on exit. Python makes the flock(2) call, because bash 3.2 has none and macOS has
# no flock(1). Every process the caller starts inherits fd 9, so an xcodebuild still holds the
# simulator after its test-sim.sh is killed. The kernel frees the lock when the last of them exits,
# so a kill -9 leaves nothing to clear. Never delete the lock file, or the next actor locks a new
# inode while the old holder still runs.

sim_flock() {
  local lock=/tmp/workout-verify-$1/lock rc=0
  python3 -c 'import fcntl, sys
try: fcntl.flock(9, getattr(fcntl, sys.argv[1]) | fcntl.LOCK_NB)
except BlockingIOError: sys.exit(75)' "$2" || rc=$?
  [ $rc -ne 75 ] || echo "$1 is held by a $(cat "$lock"); wait for it to finish, or use another simulator (lsof $lock lists every process holding it)" >&2
  [ $rc -eq 0 ] || exit $rc
}

claim_sim() {
  local dir=/tmp/workout-verify-$1 pid run
  mkdir -p "$dir"
  exec 9>>"$dir/lock"
  sim_flock "$1" LOCK_EX
  printf '%s (pid %s)\n' "$2" "$$" > "$dir/lock"
  # A verify app outlives the launch that recorded it, so its pid file is its claim.
  pid=$(cat "$dir/pid" 2>/dev/null) && kill -0 "$pid" 2>/dev/null || return 0
  run=$(cat "$dir/run" 2>/dev/null) || true
  echo "a verify run${run:+ $run} owns the app on $1 (pid $pid); if it is yours, run: ${run:+VERIFY_RUN=$run }.claude/skills/verify/verify.sh stop, else use another simulator" >&2
  exit 75
}

sim_free() {
  [ -f "/tmp/workout-verify-$1/lock" ] || return 0
  sim_flock "$1" LOCK_SH 9<"/tmp/workout-verify-$1/lock"
}
