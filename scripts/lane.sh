#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/lane.sh up <name> <commit>
       scripts/lane.sh env <name>
       scripts/lane.sh down [--if-idle <days>] <name>
       scripts/lane.sh assess <name> <idle-days>

A lane is a detached worktree, a simulator, and an evidence directory, all derived from its name, which
matches ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$. For the checkout this script belongs to (the primary):
  worktree   <primary>/.claude/worktrees/<name>, detached
  simulator  workout-lane-<name>, from scripts/sim-pool.sh
  evidence   <primary>/.claude/work/evidence/detached-<name>, verify.sh's default for that worktree

  up      create whatever is missing and print the env; a rerun prints the same lines. Fetches origin
          when <commit> is not here yet. Runs .githooks/post-checkout in the worktree, so it has
          Secrets.xcconfig. Leaves the simulator Shutdown; test-sim.sh and verify.sh boot it.
  env     print the env of an existing lane; reads only.
  down    save what removal would lose to <evidence>/down-<YYYYmmdd-HHMMSS>/ (head.txt,
          uncommitted.diff, untracked.tar of untracked and ignored-but-not-regenerable files,
          commits.bundle of commits no ref holds, copies of .build/test-sim and .build/verify), then
          remove the worktree, its DerivedData, and its simulator. Each step skips what is already gone,
          so a second down exits 0. --if-idle removes only when assess says remove.
  assess  print `keep<TAB><reason>` or `remove<TAB>idle Nd`. scripts/prune-merged-worktrees.sh runs it
          for every detached worktree under .claude/worktrees/. Keeps a lane that is not a registered
          worktree, is on a branch, is locked, holds a nested worktree, has uncommitted changes or
          ignored files that are work, holds commits no ref holds, is in use (a process cwd inside it or
          its simulator's verify lock), or was active within <idle-days>.

up and env print exactly three lines, every value single-quoted, so bash, zsh, and fish run them alike:
  export SIM='<udid>'
  export LANE_WORKTREE='<worktree>'
  export VERIFY_EVIDENCE='<evidence>'
Each later Bash call re-derives them, for example:
  env=$(scripts/lane.sh env e8) && eval "$env" && "$LANE_WORKTREE/scripts/test-sim.sh" unit

Exit codes: 0 done; 1 env: no such lane, or down --if-idle: the lane is not idle (stderr SKIPPED:
<reason>); 2 usage, a bad name, an unknown commit, a lane at another commit, a worktree on a branch,
a locked lane or one holding a nested worktree, or down run from the lane's own copy of this script;
69 the simulator runtime is missing; 70 git, simctl, or a save failed (down then removes nothing); 75 a test-sim or verify run holds
the lane's simulator, or the simulator pool is busy.
EOF
  exit 2
}

die() { echo "lane.sh: $2" >&2; exit "$1"; }

unset GIT_DIR GIT_WORK_TREE
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$here/sim-lock.sh"
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir) || die 2 "$here is not in a git checkout"
primary=$(dirname "$common")
case $primary in *"'"* | *$'\n'*) die 2 "the checkout path holds a quote or a newline, which the printed env cannot carry: $primary" ;; esac

set_lane() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || usage
  name=$1
  wt=$primary/.claude/worktrees/$name
  evidence=$primary/.claude/work/evidence/detached-$name
}

whole_days() { case $1 in '' | *[!0-9]*) usage ;; esac; }

# The porcelain lines of the lane's worktree record (HEAD, detached or branch, locked), empty when git
# does not list it.
registration() {
  git -C "$primary" worktree list --porcelain | awk -v w="worktree $wt" '$0 == w { f = 1; next } f && $0 == "" { exit } f'
}

field() { printf '%s\n' "$1" | sed -n "s|^$2||p"; }

nested_worktree() {
  git -C "$primary" worktree list --porcelain | sed -n 's/^worktree //p' | awk -v p="$wt/" 'index($0, p) == 1 { print; exit }'
}

lane_udids() {
  "$here/sim-pool.sh" list | awk -F '\t' -v n="workout-lane-$name" '$3 == "lane" && $4 == n { print $1 }'
}

# Ignored paths that are work. Everything a build or the bootstrap regenerates is left out.
ignored_work() {
  git -c core.quotePath=false -C "$wt" ls-files -o -i --exclude-standard --directory --no-empty-directory \
    | awk '{ p = $0; sub(/\/$/, "", p); n = split(p, part, "/"); base = part[n] }
      base == ".build" || base == ".swiftpm" || base == "Secrets.xcconfig" || base == "xcuserdata" \
        || base == ".DS_Store" || base == "__pycache__" || base == ".venv" { next }
      { print }'
}

ref_holds_head() {
  local holders
  holders=$(git -C "$wt" for-each-ref --count=1 --contains HEAD refs/heads refs/remotes refs/tags) || return 2
  [ -n "$holders" ]
}

cwd_holder() {
  local cwds
  cwds=$(lsof -a -d cwd -Fpn 2>/dev/null) || true
  [ -n "$cwds" ] || return 1
  printf '%s\n' "$cwds" | awk -v w="$wt" -v me=$$ '/^p/ { pid = substr($0, 2) }
    /^n/ { n = substr($0, 2); if ((n == w || index(n, w "/") == 1) && pid != me) { print pid; exit } }'
}

# Newest mtime, in epoch seconds, of each path and of what lies up to <depth> levels below it.
newest_mtime() {
  python3 -c 'import os, sys
def times(path, depth):
    try: yield os.lstat(path).st_mtime
    except OSError: return
    if depth and os.path.isdir(path) and not os.path.islink(path):
        for entry in os.listdir(path): yield from times(os.path.join(path, entry), depth - 1)
found = [t for arg in sys.argv[1:] for t in times(arg.rsplit(":", 1)[0], int(arg.rsplit(":", 1)[1]))]
if found: print(int(max(found)))' "$@"
}

# Sets verdict and reason. Ordered, first match wins, and a fact it cannot read keeps the lane: the
# index is not an activity mark because git status rewrites it, and the HEAD commit date is not one
# because a fresh lane can sit on an old commit.
assess() {
  local days=$1 reg branch porcelain work admin created head udid lock pid newest age
  verdict=keep
  reg=$(registration)
  if [ -z "$reg" ]; then reason="not a registered worktree"; return; fi
  branch=$(field "$reg" 'branch refs/heads/')
  if [ -n "$branch" ]; then reason="on branch $branch; the PR rows decide"; return; fi
  if printf '%s\n' "$reg" | grep -q '^locked'; then reason="locked"; return; fi
  work=$(nested_worktree)
  if [ -n "$work" ]; then reason="holds the worktree $work"; return; fi
  if ! porcelain=$(git -C "$wt" status --porcelain --ignore-submodules=none 2>/dev/null); then
    reason="could not read the working tree status"; return
  fi
  if [ -n "$porcelain" ]; then reason="uncommitted changes ($(printf '%s\n' "$porcelain" | grep -c .))"; return; fi
  if ! work=$(ignored_work 2>/dev/null); then reason="could not list ignored files"; return; fi
  if [ -n "$work" ]; then reason="ignored files that are work: $(printf '%s\n' "$work" | head -1)"; return; fi
  if ! admin=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) \
    || ! head=$(git -C "$wt" rev-parse HEAD 2>/dev/null); then
    reason="could not read HEAD"; return
  fi
  created=$(head -1 "$admin/logs/HEAD" 2>/dev/null | cut -d ' ' -f2) || true
  if [ -z "$created" ]; then reason="could not read the creation commit in $admin/logs/HEAD"; return; fi
  if [ "$head" != "$created" ]; then
    if ref_holds_head 2>/dev/null; then :
    elif [ $? = 1 ]; then reason="commits no ref holds"; return
    else reason="could not list the refs that hold HEAD"; return
    fi
  fi
  if ! pid=$(cwd_holder); then reason="could not list process working directories"; return; fi
  if [ -n "$pid" ]; then reason="in use by pid $pid"; return; fi
  if ! udid=$(lane_udids 2>/dev/null); then reason="could not list simulators"; return; fi
  for udid in $udid; do
    lock=/tmp/workout-verify-$udid/lock
    if ! (require_sim_free "$udid") 2>/dev/null; then reason="in use by $(cat "$lock" 2>/dev/null)"; return; fi
  done
  newest=$(newest_mtime "$admin/logs/HEAD:0" "$admin/HEAD:0" "$wt/.build:2" "$evidence:2")
  if [ -z "$newest" ]; then reason="could not read activity times"; return; fi
  age=$((($(date +%s) - newest) / 86400))
  if [ "$age" -lt "$days" ]; then reason="active ${age}d ago, threshold ${days}d"; return; fi
  verdict=remove
  reason="idle ${age}d"
}

print_env() {
  printf "export SIM='%s'\nexport LANE_WORKTREE='%s'\nexport VERIFY_EVIDENCE='%s'\n" "$1" "$wt" "$evidence"
}

resolve() { git -C "$primary" rev-parse --verify -q "$1^{commit}"; }

lane_up() {
  local commit=$2 sha reg head branch udid
  set_lane "$1"
  if ! sha=$(resolve "$commit"); then
    echo "lane.sh: $commit is not here; fetching origin" >&2
    git -C "$primary" fetch -q origin >&2 || true
    if ! sha=$(resolve "$commit"); then
      if [[ $commit =~ ^[0-9a-f]{40}$ ]]; then git -C "$primary" fetch -q origin "$commit" >&2 2>/dev/null || true; fi
      sha=$(resolve "$commit") || die 2 "unknown commit $commit, even after fetching origin"
    fi
  fi
  git -C "$primary" worktree prune
  reg=$(registration)
  if [ -z "$reg" ]; then
    [ ! -e "$wt" ] || die 2 "$wt exists but git does not list it as a worktree; move it away first"
    mkdir -p "$(dirname "$wt")"
    git -C "$primary" worktree add --detach "$wt" "$sha" >&2 || true
    reg=$(registration)
    [ -n "$reg" ] || die 70 "git worktree add $wt $sha failed"
  fi
  head=$(field "$reg" 'HEAD ')
  branch=$(field "$reg" 'branch refs/heads/')
  [ -z "$branch" ] && [ "$head" = "$sha" ] \
    || die 2 "lane $name is at $head${branch:+ on branch $branch}, not $sha; lane.sh down $name first"
  if [ -f "$wt/.githooks/post-checkout" ]; then
    (cd "$wt" && sh .githooks/post-checkout) >&2 || die 70 "the post-checkout hook failed in $wt"
  fi
  udid=$("$here/sim-pool.sh" create "$name")
  mkdir -p "$evidence"
  print_env "$udid"
}

lane_env() {
  local udid
  set_lane "$1"
  [ -n "$(registration)" ] && [ -d "$wt" ] || die 1 "no lane $1; run lane.sh up $1 <commit>"
  udid=$(lane_udids)
  [ -n "$udid" ] || die 1 "no lane $1; run lane.sh up $1 <commit>"
  [ "$(printf '%s\n' "$udid" | grep -c .)" -eq 1 ] || die 70 "two simulators are named workout-lane-$1; scripts/sim-pool.sh list shows them"
  print_env "$udid"
}

# Prints the name of each file it saved. Any failure exits 70 before anything is removed.
save_lane() {
  local dir=$1 list d
  mkdir -p "$dir" || die 70 "could not create $dir"
  git -C "$wt" log -1 --format='%H %s' >"$dir/head.txt" || die 70 "could not save head.txt"
  echo head.txt
  git -C "$wt" diff --binary HEAD >"$dir/uncommitted.diff" || die 70 "could not save uncommitted.diff"
  if [ -s "$dir/uncommitted.diff" ]; then echo uncommitted.diff; else rm -f "$dir/uncommitted.diff"; fi
  list=$(mktemp)
  { git -c core.quotePath=false -C "$wt" ls-files -o --exclude-standard && ignored_work; } >"$list" \
    || { rm -f "$list"; die 70 "could not list untracked files"; }
  if [ -s "$list" ]; then
    tar -cf "$dir/untracked.tar" -C "$wt" -T "$list" && tar -tf "$dir/untracked.tar" >/dev/null \
      || { rm -f "$list"; die 70 "could not save untracked.tar"; }
    echo untracked.tar
  fi
  rm -f "$list"
  if ! ref_holds_head 2>/dev/null; then
    git -C "$wt" bundle create "$dir/commits.bundle" HEAD --not --branches --remotes --tags 2>/dev/null \
      && git -C "$wt" bundle verify "$dir/commits.bundle" >/dev/null 2>&1 \
      || die 70 "could not save commits.bundle"
    echo commits.bundle
  fi
  for d in test-sim verify; do
    [ -d "$wt/.build/$d" ] || continue
    cp -cR "$wt/.build/$d" "$dir/$d" 2>/dev/null || { rm -rf "${dir:?}/$d" && cp -R "$wt/.build/$d" "$dir/$d"; } \
      || die 70 "could not copy .build/$d"
    echo "$d"
  done
}

derived_data_of() {
  python3 -c 'import glob, os, plistlib, sys
for d in sorted(glob.glob(os.path.join(sys.argv[1], "WorkoutTracker-*"))):
    try:
        with open(os.path.join(d, "info.plist"), "rb") as f: path = plistlib.load(f).get("WorkspacePath")
    except Exception: continue
    if path == sys.argv[2]: print(d)' "$HOME/Library/Developer/Xcode/DerivedData" "$1"
}

lane_down() {
  local idle= udid reg branch work dir saved removed=0 d
  if [ "${1:-}" = --if-idle ]; then
    [ $# -eq 3 ] || usage
    whole_days "$2"
    idle=$2
    shift 2
  fi
  [ $# -eq 1 ] || usage
  set_lane "$1"
  case "$here/" in "$wt/"*) die 2 "this copy of lane.sh lives in lane $name; run $primary/scripts/lane.sh down $name" ;; esac
  if [ -n "$idle" ]; then
    assess "$idle"
    [ "$verdict" = remove ] || { echo "SKIPPED: $reason" >&2; exit 1; }
  fi
  udid=$(lane_udids)
  for d in $udid; do require_sim_free "$d"; done
  git -C "$primary" worktree prune
  reg=$(registration)
  if [ -n "$reg" ]; then
    branch=$(field "$reg" 'branch refs/heads/')
    [ -z "$branch" ] || die 2 "$wt is on branch $branch, not a lane; prune-merged-worktrees.sh decides branch worktrees"
    ! printf '%s\n' "$reg" | grep -q '^locked' || die 2 "lane $name is locked; git worktree unlock $wt first"
    work=$(nested_worktree)
    [ -z "$work" ] || die 2 "lane $name holds the worktree $work; remove that first"
    dir=$evidence/down-$(date +%Y%m%d-%H%M%S)
    saved=$(save_lane "$dir")
    echo "lane.sh: saved $(printf '%s\n' "$saved" | tr '\n' ' ')to $dir" >&2
    git -C "$primary" worktree remove --force "$wt" >&2 || die 70 "git worktree remove $wt failed"
    echo "lane.sh: removed the worktree $wt" >&2
  elif [ -e "$wt" ]; then
    echo "lane.sh: left $wt alone, because git does not list it as a worktree" >&2
  fi
  while IFS= read -r d; do
    rm -rf "$d"
    removed=$((removed + 1))
  done < <(derived_data_of "$wt/WorkoutTracker.xcodeproj")
  [ "$removed" -eq 0 ] || echo "lane.sh: removed $removed DerivedData dir(s)" >&2
  "$here/sim-pool.sh" delete "$name"
}

[ $# -ge 1 ] || usage
command=$1
shift
case $command in
  up) [ $# -eq 2 ] || usage; lane_up "$@" ;;
  env) [ $# -eq 1 ] || usage; lane_env "$1" ;;
  down) lane_down "$@" ;;
  assess)
    [ $# -eq 2 ] || usage
    whole_days "$2"
    set_lane "$1"
    assess "$2"
    printf '%s\t%s\n' "$verdict" "$reason"
    ;;
  *) usage ;;
esac
