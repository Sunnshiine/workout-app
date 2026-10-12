# shellcheck shell=bash
# The slot locks live under the git dir, where neither git clean -x nor rm -rf .build reaches: a
# deleted lock file would let a second run take a slot the first still holds.

# Sets $scratch to a slot locked for this process. Call it directly, never through $(...): the lock
# lives on fd 8 of the calling shell, and its exit 75 must end the caller. fd 9 is sim-lock.sh's
# simulator lock, which the slot's test-sim.sh takes and closes for its children.
scratch_claim() {
  local who=$1 n preferred="" others="" holders=""
  _scratch_paths
  for n in $(seq 1 "${SCRATCH_SLOTS:-4}"); do
    if [ "$(cat "$locks/$n.owner" 2>/dev/null)" = "$caller" ]; then
      preferred="$preferred $n"
    else
      others="$others $n"
    fi
  done
  for n in $preferred $others; do
    if _scratch_lock "$n" "$who"; then
      printf '%s\n' "$caller" >"$locks/$n.owner"
      scratch=$pool/$n
      _scratch_ensure "$caller"
      return 0
    fi
    holders="$holders
  $pool/$n: $(cat "$locks/$n.lock")"
  done
  echo "every scratch tree is busy; wait for one to finish (lsof $locks/*.lock lists every holder):$holders" >&2
  exit 75
}

# A git fsmonitor daemon started from a slot would inherit fd 8 and hold the slot for as long as it
# lives. The repo's post-checkout hook would run on every per-mutant restore, and its exit status
# would become checkout's.
_scratch_paths() {
  local common
  export GIT_CONFIG_COUNT=$((${GIT_CONFIG_COUNT:-0} + 2))
  export "GIT_CONFIG_KEY_$((GIT_CONFIG_COUNT - 2))=core.fsmonitor" "GIT_CONFIG_VALUE_$((GIT_CONFIG_COUNT - 2))=false"
  export "GIT_CONFIG_KEY_$((GIT_CONFIG_COUNT - 1))=core.hooksPath" "GIT_CONFIG_VALUE_$((GIT_CONFIG_COUNT - 1))=/dev/null"
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  pool=$(dirname "$common")/.build/scratch
  locks=$common/scratch-locks
  caller=$(git rev-parse --show-toplevel)
  mkdir -p "$pool" "$locks"
}

# Locks slot N on fd 8 and records WHO and this pid in its lock file. A lock whose recorded pid is dead
# is held only by processes its run left behind, such as a test orphaned by a SIGKILL to the run's
# process group; they are killed and the slot taken.
_scratch_lock() {
  local lock=$locks/$1.lock record pid leftovers
  exec 8>>"$lock"
  if _scratch_flock "$2 (pid $$)" 0; then return 0; fi
  exec 8>&-
  record=$(cat "$lock")
  pid=${record##*(pid }
  pid=${pid%)}
  case $pid in '' | *[!0-9]*) return 1 ;; esac
  ! kill -0 "$pid" 2>/dev/null || return 1
  leftovers=$(lsof -t "$lock" 2>/dev/null) || true
  [ "$(cat "$lock")" = "$record" ] || return 1
  # shellcheck disable=SC2086  # one pid per word
  [ -z "$leftovers" ] || kill -KILL $leftovers 2>/dev/null || true
  exec 8>>"$lock"
  if _scratch_flock "$2 (pid $$)" 5; then return 0; fi
  exec 8>&-
  return 1
}

# Takes the lock on fd 8, waiting up to SECONDS, then writes RECORD into the lock file in the same
# process, so a claim never reads the previous holder's record under a fresh lock.
_scratch_flock() {
  python3 -c 'import fcntl, os, sys, time
deadline = time.time() + float(sys.argv[2])
while True:
    try:
        fcntl.flock(8, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.time() >= deadline:
            sys.exit(1)
        time.sleep(0.1)
os.ftruncate(8, 0)
os.write(8, (sys.argv[1] + "\n").encode())' "$1" "$2"
}

_scratch_ensure() {
  local caller=$1
  if ! { [ -f "$scratch/.git" ] && git -C "$scratch" rev-parse -q --verify HEAD >/dev/null 2>&1; }; then
    git worktree prune
    rm -rf "$scratch"
    git worktree add -q --detach --force "$scratch" HEAD
  fi
  if [ -f "$caller/Secrets.xcconfig" ]; then
    cmp -s "$caller/Secrets.xcconfig" "$scratch/Secrets.xcconfig" || cp "$caller/Secrets.xcconfig" "$scratch/Secrets.xcconfig"
  elif [ ! -f "$scratch/Secrets.xcconfig" ] && [ -f "$scratch/.githooks/post-checkout" ]; then
    (cd "$scratch" && sh .githooks/post-checkout) || true
  fi
}

# Prints the tree of the caller's working state: HEAD plus staged, unstaged, and untracked files that
# are not ignored.
scratch_snapshot() {
  local index status=0
  index=$(mktemp)
  cp "$(git rev-parse --path-format=absolute --git-path index)" "$index" &&
    GIT_INDEX_FILE=$index git add -A &&
    GIT_INDEX_FILE=$index git write-tree || status=$?
  rm -f "$index"
  return $status
}

# Puts the slot at COMMIT, then the files of TREE on top when given.
scratch_sync() {
  git -C "$scratch" checkout -q --detach -f "$1"
  if [ -n "${2:-}" ]; then
    git -C "$scratch" read-tree --reset -u "$2"
  fi
  git -C "$scratch" clean -fdq
}
