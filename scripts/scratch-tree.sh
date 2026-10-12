# shellcheck shell=bash
# The slot locks live under the git dir, where neither git clean -x nor rm -rf .build reaches: a
# deleted lock file would let a second run take a slot the first still holds.

# Sets $scratch to a slot locked for this process. Call it directly, never through $(...): the lock
# lives on fd 8 of the calling shell, and its exit 75 must end the caller. fd 9 is sim-lock.sh's
# simulator lock, which the slot's test-sim.sh takes and closes for its children.
scratch_claim() {
  local who=$1 n preferred="" others="" holders=""
  _scratch_env
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
  $pool/$n: $held_by"
  done
  echo "every scratch tree is busy; wait for one to finish (lsof $locks/*.lock lists every holder):$holders" >&2
  exit 75
}

# Removes every slot no live run holds, with the DerivedData its simulator builds left, including
# DerivedData whose slot folder is already gone.
scratch_clean() {
  local n slots="" plist workspace paths
  _scratch_env
  for n in "$pool"/*; do slots="$slots ${n##*/}"; done
  for plist in ~/Library/Developer/Xcode/DerivedData/WorkoutTracker-*/info.plist; do
    workspace=$(plutil -extract WorkspacePath raw "$plist" 2>/dev/null) || continue
    case $workspace in "$pool"/*/WorkoutTracker.xcodeproj) n=${workspace#"$pool"/}; slots="$slots ${n%%/*}" ;; esac
  done
  for n in $(printf '%s\n' $slots | grep -x '[0-9][0-9]*' | sort -un); do
    if ! _scratch_lock "$n" "mutate.sh --clean-scratch"; then
      echo "kept $pool/$n: $held_by"
      continue
    fi
    paths=()
    [ ! -d "$pool/$n" ] || paths+=("$pool/$n")
    for plist in ~/Library/Developer/Xcode/DerivedData/WorkoutTracker-*/info.plist; do
      [ "$(plutil -extract WorkspacePath raw "$plist" 2>/dev/null)" != "$pool/$n/WorkoutTracker.xcodeproj" ] ||
        paths+=("${plist%/info.plist}")
    done
    echo "removed $pool/$n ($(($(du -sk "${paths[@]}" | awk '{ kb += $1 } END { print kb }') / 1024)) MB)"
    git worktree remove --force "$pool/$n" 2>/dev/null || true
    rm -rf "${paths[@]}" "$locks/$n.owner"
    exec 8>&-
  done
  git worktree prune
}

# A git fsmonitor daemon started from a slot would inherit fd 8 and hold the slot for as long as it
# lives. The repo's post-checkout hook would run on every per-mutant restore, and its exit status
# would become checkout's.
_scratch_env() {
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

# fd 7 holds claim.lock while one claim probes one slot, so any other process with a slot's lock file
# open holds that slot or was started by the run that did. A slot whose recorded pid is dead is held
# only by such leftovers; they are killed and the slot taken. On failure, $held_by is the holder's
# record, read under claim.lock.
_scratch_lock() {
  local lock=$locks/$1.lock pid status=1
  exec 7>>"$locks/claim.lock"
  _scratch_flock 7 60 || { echo "$locks/claim.lock stayed locked for 60 s (lsof lists its holder)" >&2; exit 75; }
  exec 8>>"$lock"
  if _scratch_flock 8 0; then
    status=0
  else
    exec 8>&-
    pid=$(sed -n 's/.*(pid \([0-9]*\))$/\1/p' "$lock")
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      lsof -t "$lock" | xargs kill -KILL 2>/dev/null || true
      exec 8>>"$lock"
      if _scratch_flock 8 5; then status=0; else exec 8>&-; fi
    fi
  fi
  if [ $status = 0 ]; then
    printf '%s (pid %s)\n' "$2" "$$" >"$lock"
  else
    held_by=$(cat "$lock")
  fi
  exec 7>&-
  return $status
}

# Takes the lock on fd FD, waiting up to SECONDS.
_scratch_flock() {
  python3 -c 'import fcntl, sys, time
deadline = time.time() + float(sys.argv[2])
while True:
    try:
        fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.time() >= deadline:
            sys.exit(1)
        time.sleep(0.1)' "$1" "$2"
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
