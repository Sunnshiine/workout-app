# shellcheck shell=bash
# A pool of detached worktrees under the primary checkout's .build/scratch/, where mutate.sh and
# check-each-commit.sh build and test, so the caller's worktree is never written. Slot paths never
# change, so each keeps one warm SwiftPM .build/ and one DerivedData dir, and the pool size bounds disk.

scratch_pool() {
  if [ -n "${SCRATCH_POOL:-}" ]; then
    echo "$SCRATCH_POOL"
  else
    echo "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.build/scratch"
  fi
}

# Sets $scratch to a slot locked for this process. Call it directly, never through $(...): the lock
# lives on fd 8 of the calling shell, and its exit 75 must end the caller.
# The lock is a flock on fd 8, which every child inherits. A killed run frees its slot when the last
# build it started exits, so no stale-pid logic exists. fd 9 stays free for test-sim.sh's
# simulator lock, which the slot's test-sim.sh takes and closes for its own children.
scratch_claim() {
  local who=$1 pool caller n preferred="" others="" holders=""
  # A git fsmonitor daemon started from here would inherit fd 8 and hold the slot until reboot.
  export GIT_CONFIG_COUNT=$((${GIT_CONFIG_COUNT:-0} + 1))
  export "GIT_CONFIG_KEY_$((GIT_CONFIG_COUNT - 1))=core.fsmonitor" "GIT_CONFIG_VALUE_$((GIT_CONFIG_COUNT - 1))=false"
  pool=$(scratch_pool)
  caller=$(git rev-parse --show-toplevel)
  mkdir -p "$pool"
  for n in $(seq 1 "${SCRATCH_SLOTS:-4}"); do
    if [ "$(cat "$pool/$n.owner" 2>/dev/null)" = "$caller" ]; then
      preferred="$preferred $n"
    else
      others="$others $n"
    fi
  done
  for n in $preferred $others; do
    exec 8>>"$pool/$n.lock"
    if python3 -c 'import fcntl, sys
try: fcntl.flock(8, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError: sys.exit(75)'; then
      printf '%s (pid %s)\n' "$who" "$$" >"$pool/$n.lock"
      printf '%s\n' "$caller" >"$pool/$n.owner"
      scratch=$pool/$n
      _scratch_ensure "$caller"
      return 0
    fi
    exec 8>&-
    holders="$holders
  $pool/$n: $(cat "$pool/$n.lock")"
  done
  echo "every scratch tree is busy; wait for one to finish (lsof $pool/*.lock lists every holder):$holders" >&2
  exit 75
}

# Converges a slot that is missing, half-created, pruned, or a plain directory into a detached worktree.
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
# are not ignored. It stages into a copy of the index, so the caller's index and files are never written.
scratch_snapshot() {
  local index status=0
  index=$(mktemp)
  cp "$(git rev-parse --path-format=absolute --git-path index)" "$index" &&
    GIT_INDEX_FILE=$index git add -A &&
    GIT_INDEX_FILE=$index git write-tree || status=$?
  rm -f "$index"
  return $status
}

# Puts the slot at COMMIT, then the files of TREE on top when given. Converges from any state,
# including a crashed run's mutant. Git rewrites only the files that differ, so builds stay warm, and
# clean has no -x, so .build/ and Secrets.xcconfig survive.
scratch_sync() {
  git -C "$scratch" checkout -q --detach -f "$1"
  if [ -n "${2:-}" ]; then
    git -C "$scratch" read-tree --reset -u "$2"
  fi
  git -C "$scratch" clean -fdq
}
