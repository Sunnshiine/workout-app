#!/bin/bash
set -euo pipefail

help() {
  cat <<'EOF'
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
          when <commit> is not here yet. Records <commit> as the lane's base when it adds the
          worktree; a rerun never moves it, so assess and down still count the lane's own commits.
          Runs .githooks/post-checkout in the worktree, so it has Secrets.xcconfig. Leaves the
          simulator Shutdown; test-sim.sh and verify.sh boot it. A worktree a crashed git worktree
          add left (locked "initializing") is removed and added again.
  env     print the env of an existing lane; reads only.
  down    delete the simulator first, so a run holding it stops down with exit 75 before anything
          else; then save what removal would lose to <evidence>/down-<YYYYmmdd-HHMMSS>/ (head.txt,
          uncommitted.diff against HEAD, staged.diff of the index against HEAD, untracked.tar of
          untracked and ignored files except regenerable ones, commits.bundle of commits no branch
          or tag holds, copies of the results dirs .build/test-sim, .build/verify without its
          node_modules, .build/crap, .build/flake-hunt, .build/mutate, and .build/check-each-commit);
          then remove the worktree and its
          DerivedData. Each step skips what is already gone, so a second down exits 0. --if-idle
          removes only when assess says remove.
  assess  print `keep<TAB><reason>` or `remove<TAB>idle Nd`. scripts/prune-merged-worktrees.sh runs it
          for every detached worktree under .claude/worktrees/. Keeps a lane that is not a registered
          worktree, is on a branch, is locked (a crashed git worktree add's lock, "initializing",
          says so and up or down repairs it), holds a nested worktree, has uncommitted changes or
          untracked files, holds commits no branch or tag holds, is in use (a process cwd inside it,
          its simulator's verify lock, or its simulator booted), or was active within <idle-days>
          (its reflog, HEAD, .build, evidence, or DerivedData changed). Ignored files keep
          nothing, because down saves them. A commit counts when HEAD or its reflog reaches it; a
          remote-tracking ref holds nothing, because the server may have deleted the branch.

up and env print exactly three lines, every value single-quoted, so bash, zsh, and fish run them alike:
  export SIM='<udid>'
  export LANE_WORKTREE='<worktree>'
  export VERIFY_EVIDENCE='<evidence>'
Each later Bash call re-derives them, for example:
  env=$(scripts/lane.sh env e8) && eval "$env" && "$LANE_WORKTREE/scripts/test-sim.sh" unit

Exit codes: 0 done; 1 env: no such lane, or down --if-idle: the lane is not idle (stderr SKIPPED:
<reason>); 2 usage, a bad WORKOUT_* setting, a bad name, a name that differs only by case from a
directory already there on a disk that ignores case, an unknown commit, a lane at another commit, a
worktree on a branch, a locked lane, one holding a nested worktree, or one registered but missing
(moved or deleted), or down run from the lane's own copy of this script;
69 the simulator runtime is missing; 70 git, simctl, or a save failed (down then leaves the worktree,
but its simulator is already gone; lane.sh up <name> <commit> makes a new one);
75 a test-sim or verify run holds the lane's simulator, the simulator pool or the host is busy (up
builds the template on first use, and its boot waits for the host as scripts/sim-pool.sh --help
says), down found another process working inside the lane (stop it or cd out; this script's callers
do not count), or another up or down of the same lane held it for WORKOUT_ADMIT_WAIT seconds
(default 540).
EOF
}

usage() { help >&2; exit 2; }

case ${1:-} in -h | --help) help; exit 0 ;; esac

die() { echo "lane.sh: $2" >&2; exit "$1"; }

# The lane lock is fd 5, because sim-lock.sh keeps fd 6 for stderr. A flock is shared by every process
# holding the fd, so no child that may outlive this script, such as git's background gc, gets it.
# Not `command git`: bash 3.2 hands a builtin's child its saved copy of fd 5.
git_bin=$(type -P git) || die 2 "git is not on PATH"
git() { "$git_bin" "$@" 5>&-; }
sim_pool() { "$here/sim-pool.sh" "$@" 5>&-; }

unset GIT_DIR GIT_WORK_TREE
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$here/sim-lock.sh"
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir) || die 2 "$here is not in a git checkout"
primary=$(dirname "$common")
case $primary in *"'"* | *$'\n'*) die 2 "the checkout path holds a quote or a newline, which the printed env cannot carry: $primary" ;; esac
cd "$primary"

set_lane() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || usage
  name=$1
  wt=$primary/.claude/worktrees/$name
  evidence=$primary/.claude/work/evidence/detached-$name
}

# Called only when $wt exists: with no entry named exactly $name, the disk resolved it by case.
case_twin() {
  ls -1 "$(dirname "$wt")" | awk -v n="$name" '$0 == n { exact = 1 } tolower($0) == tolower(n) && twin == "" { twin = $0 }
    END { if (!exact) print twin }'
}

lock_lane() {
  local lock=$host_lock_dir/lane-$name rc=0
  exec 5>>"$lock"
  try_flock 5 LOCK_EX $((WORKOUT_ADMIT_WAIT * 20 + 1)) || rc=$?
  [ $rc -ne 75 ] || die 75 "waited $WORKOUT_ADMIT_WAIT s for lane $name, held by $(cat "$lock") (lsof $lock lists it)"
  [ $rc -eq 0 ] || exit $rc
  printf 'lane.sh %s %s (pid %s)\n' "$1" "$name" "$$" >"$lock"
}

whole_days() { case $1 in '' | *[!0-9]*) usage ;; esac; }

registration() {
  git -C "$primary" worktree list --porcelain | awk -v w="worktree $wt" '$0 == w { f = 1; next } $0 == "" { f = 0 } f'
}

# The record of a moved worktree still holds its reflog and per-worktree refs, and git worktree
# repair reconnects them, so neither up nor down drops it.
refuse_missing() {
  grep -q '^prunable' <<<"$reg" || return 0
  die 2 "$wt is registered but missing; if you moved it, run git worktree repair <new path>; to discard it and anything only it holds, git worktree remove --force $wt"
}

# git worktree add locks its record "initializing" until it finishes, so that lock is a crash, not
# a human's.
crashed_add() { printf '%s\n' "$reg" | grep -qx 'locked initializing'; }

field() { printf '%s\n' "$1" | sed -n "s|^$2||p"; }

nested_worktree() {
  git -C "$primary" worktree list --porcelain | sed -n 's/^worktree //p' | awk -v p="$wt/" '!found && index($0, p) == 1 { print; found = 1 }'
}

lane_sims() {
  sim_pool list | awk -F '\t' -v n="workout-lane-$name" '$3 == "lane" && $4 == n { print $1 "\t" $2 }'
}

lane_udids() { lane_sims | cut -f1; }

files_to_save() {
  git -C "$wt" ls-files -z -o --exclude-standard
  git -C "$wt" ls-files -z -o -i --exclude-standard --directory --no-empty-directory | python3 -c '
import sys
regenerable = {b".build", b".swiftpm", b"Secrets.xcconfig", b"xcuserdata", b".DS_Store", b"__pycache__", b".venv",
               b"default.profraw", b".xcodebuildmcp", b"node_modules", b".codex"}
for path in sys.stdin.buffer.read().split(b"\0"):
    parts = path.rstrip(b"/").split(b"/")
    if not path or regenerable.intersection(parts) or parts[-1].endswith(b".pyc") \
            or path == b".claude/settings.local.json":
        continue
    sys.stdout.buffer.write(path + b"\0")'
}

# up records the lane's base in refs/worktree/lane-base, because gc expires reflog entries, the
# creation entry first. A lane up did not make has a base only while that entry survives.
read_lane_history() {
  local reflog
  reflog=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)/logs/HEAD || return 1
  visited=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || return 1
  [ -f "$reflog" ] || reflog=/dev/null
  base=$(git -C "$wt" rev-parse -q --verify refs/worktree/lane-base) \
    || base=$(awk 'NR == 1 && $1 ~ /^0+$/ { print $2 }' "$reflog") || return 1
  visited=$visited$'\n'$(awk '{ for (i = 1; i <= 2; i++) if ($i !~ /^0+$/) print $i }' "$reflog" | sort -u) || return 1
}

unique_commits() {
  git -C "$wt" rev-list $visited --not --branches --tags $base
}

cwd_holder() {
  local cwds skip=" $$ " p=$$
  while p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') && [ -n "$p" ] && [ "$p" -gt 1 ]; do skip="$skip$p "; done
  cwds=$(lsof -a -d cwd -Fpcn 2>/dev/null) || true
  [ -n "$cwds" ] || return 1
  awk -v w="$wt" -v skip="$skip" '/^p/ { pid = substr($0, 2) } /^c/ { cmd = substr($0, 2) }
    /^n/ && !found { n = substr($0, 2); if ((n == w || index(n, w "/") == 1) && !index(skip, " " pid " ")) { print pid " " cmd; found = 1 } }' <<<"$cwds"
}

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

assess() {
  local days=$1 reg branch porcelain work admin commits holder sims udid state lock derived d marks newest age
  verdict=keep
  reg=$(registration)
  if [ -z "$reg" ]; then reason="not a registered worktree"; return; fi
  branch=$(field "$reg" 'branch refs/heads/')
  if [ -n "$branch" ]; then reason="on branch $branch; the PR rows decide"; return; fi
  if crashed_add; then reason="a git worktree add crashed here; lane.sh up or down repairs it"; return; fi
  if printf '%s\n' "$reg" | grep -q '^locked'; then reason="locked"; return; fi
  work=$(nested_worktree)
  if [ -n "$work" ]; then reason="holds the worktree $work"; return; fi
  if ! porcelain=$(git -C "$wt" status --porcelain --ignore-submodules=none 2>/dev/null); then
    reason="could not read the working tree status"; return
  fi
  if [ -n "$porcelain" ]; then reason="uncommitted changes ($(printf '%s\n' "$porcelain" | grep -c .))"; return; fi
  if ! read_lane_history || ! commits=$(unique_commits 2>/dev/null) \
    || ! admin=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null); then
    reason="could not list the commits no branch or tag holds"; return
  fi
  if [ -n "$commits" ]; then reason="commits no branch or tag holds ($(printf '%s\n' "$commits" | grep -c .))"; return; fi
  if ! holder=$(cwd_holder); then reason="could not list process working directories"; return; fi
  if [ -n "$holder" ]; then reason="in use by pid ${holder%% *} (${holder#* })"; return; fi
  if ! sims=$(lane_sims 2>/dev/null); then reason="could not list simulators"; return; fi
  while IFS=$'\t' read -r udid state; do
    [ -n "$udid" ] || continue
    lock=/tmp/workout-verify-$udid/lock
    if ! (require_sim_free "$udid") 2>/dev/null; then reason="in use by $(cat "$lock" 2>/dev/null)"; return; fi
    case $state in Booted | Booting) reason="simulator $udid is booted"; return ;; esac
  done <<<"$sims"
  if ! derived=$(derived_data_of "$wt/WorkoutTracker.xcodeproj"); then reason="could not read DerivedData"; return; fi
  # The index is not an activity mark, because git status rewrites it.
  marks=("$admin/logs/HEAD:0" "$admin/HEAD:0" "$wt/.build:2" "$evidence:2")
  while IFS= read -r d; do [ -z "$d" ] || marks+=("$d:2"); done <<<"$derived"
  newest=$(newest_mtime "${marks[@]}")
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
  local commit=$2 sha reg head branch udid twin
  set_lane "$1"
  lock_lane up
  if ! sha=$(resolve "$commit"); then
    echo "lane.sh: $commit is not here; fetching origin" >&2
    git -C "$primary" fetch -q origin >&2 || true
    if ! sha=$(resolve "$commit"); then
      if [[ $commit =~ ^[0-9a-f]{40}$ ]]; then git -C "$primary" fetch -q origin "$commit" >&2 2>/dev/null || true; fi
      sha=$(resolve "$commit") || die 2 "unknown commit $commit, even after fetching origin"
    fi
  fi
  reg=$(registration)
  refuse_missing
  if crashed_add; then
    echo "lane.sh: a git worktree add crashed in $wt; adding it again" >&2
    git -C "$primary" worktree unlock "$wt" && git -C "$primary" worktree remove --force "$wt" >&2 \
      || die 70 "could not remove the worktree a crashed git worktree add left in $wt"
    reg=$(registration)
  fi
  if [ -z "$reg" ]; then
    if [ -e "$wt" ]; then
      twin=$(case_twin)
      [ -z "$twin" ] || die 2 "$wt is the directory $twin, because this disk ignores case; pick a name that differs by more than case"
      die 2 "$wt exists but git does not list it as a worktree; move it away first"
    fi
    mkdir -p "$(dirname "$wt")"
    git -C "$primary" worktree add --detach "$wt" "$sha" >&2 || true
    reg=$(registration)
    [ -n "$reg" ] || die 70 "git worktree add $wt $sha failed"
    git -C "$wt" update-ref refs/worktree/lane-base "$sha" || die 70 "could not record the base of lane $name"
  fi
  head=$(field "$reg" 'HEAD ')
  branch=$(field "$reg" 'branch refs/heads/')
  [ -z "$branch" ] && [ "$head" = "$sha" ] \
    || die 2 "lane $name is at $head${branch:+ on branch $branch}, not $sha; lane.sh down $name first"
  if [ -f "$wt/.githooks/post-checkout" ]; then
    (cd "$wt" && sh .githooks/post-checkout) >&2 5>&- || die 70 "the post-checkout hook failed in $wt"
  fi
  udid=$(sim_pool create "$name")
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

# A bundle records only refs, so each tip other than HEAD gets a per-worktree ref,
# which git worktree remove deletes with the lane.
save_commits() {
  local head tip tips args=()
  head=$(git -C "$wt" rev-parse HEAD) || return
  tips=$(printf '%s\n' $visited | grep -Fx -f <(printf '%s\n' "$commits") | sort -u) || return
  for tip in $(git -C "$wt" merge-base --independent $tips); do
    if [ "$tip" = "$head" ]; then
      args+=(HEAD)
    else
      git -C "$wt" update-ref "refs/worktree/lane-save/$tip" "$tip" || return
      args+=("refs/worktree/lane-save/$tip")
    fi
  done
  git -C "$wt" bundle create "$1" "${args[@]}" --not --branches --tags $base 2>/dev/null \
    && git -C "$wt" bundle verify "$1" >/dev/null 2>&1
}

# verify.sh installs its driver in .build/verify/node_modules, which npm makes again.
copy_results() {
  local entry base
  mkdir -p "$dir/$1" || return
  for entry in "$wt/.build/$1"/* "$wt/.build/$1"/.[!.]* "$wt/.build/$1"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    base=${entry##*/}
    [ "$base" != node_modules ] || continue
    cp -cR "$entry" "$dir/$1/$base" 2>/dev/null || { rm -rf "${dir:?}/$1/$base" && cp -R "$entry" "$dir/$1/$base"; } || return
  done
}

save_lane() {
  local dir=$1 list d commits
  mkdir -p "$dir" || die 70 "could not create $dir"
  git -C "$wt" log -1 --format='%H %s' >"$dir/head.txt" || die 70 "could not save head.txt"
  echo head.txt
  git -C "$wt" diff --binary HEAD >"$dir/uncommitted.diff" || die 70 "could not save uncommitted.diff"
  if [ -s "$dir/uncommitted.diff" ]; then echo uncommitted.diff; else rm -f "$dir/uncommitted.diff"; fi
  git -C "$wt" diff --binary --cached HEAD >"$dir/staged.diff" || die 70 "could not save staged.diff"
  if [ -s "$dir/staged.diff" ]; then echo staged.diff; else rm -f "$dir/staged.diff"; fi
  list=$(mktemp)
  files_to_save >"$list" || { rm -f "$list"; die 70 "could not list untracked files"; }
  if [ -s "$list" ]; then
    tar -cf "$dir/untracked.tar" -C "$wt" --null -T "$list" && tar -tf "$dir/untracked.tar" >/dev/null \
      || { rm -f "$list"; die 70 "could not save untracked.tar"; }
    echo untracked.tar
  fi
  rm -f "$list"
  read_lane_history && commits=$(unique_commits) || die 70 "could not list the commits no branch or tag holds"
  if [ -n "$commits" ]; then
    save_commits "$dir/commits.bundle" || die 70 "could not save commits.bundle"
    echo commits.bundle
  fi
  for d in test-sim verify crap flake-hunt mutate check-each-commit; do
    [ -d "$wt/.build/$d" ] || continue
    copy_results "$d" || die 70 "could not copy .build/$d"
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
  local idle= reg branch work holder dir saved removed=0 d twin
  if [ "${1:-}" = --if-idle ]; then
    [ $# -eq 3 ] || usage
    whole_days "$2"
    idle=$2
    shift 2
  fi
  [ $# -eq 1 ] || usage
  set_lane "$1"
  case "$here/" in "$wt/"*) die 2 "this copy of lane.sh lives in lane $name; run $primary/scripts/lane.sh down $name" ;; esac
  lock_lane down
  if [ -n "$idle" ]; then
    assess "$idle"
    [ "$verdict" = remove ] || { echo "SKIPPED: $reason" >&2; exit 1; }
  fi
  reg=$(registration)
  refuse_missing
  if [ -n "$reg" ]; then
    branch=$(field "$reg" 'branch refs/heads/')
    [ -z "$branch" ] || die 2 "$wt is on branch $branch, not a lane; prune-merged-worktrees.sh decides branch worktrees"
    if ! crashed_add && printf '%s\n' "$reg" | grep -q '^locked'; then
      die 2 "lane $name is locked; git worktree unlock $wt first"
    fi
    work=$(nested_worktree)
    [ -z "$work" ] || die 2 "lane $name holds the worktree $work; remove that first"
    holder=$(cwd_holder) || die 70 "could not list process working directories"
    [ -z "$holder" ] || die 75 "pid ${holder%% *} (${holder#* }) works in $wt; stop it or cd out"
    if crashed_add; then git -C "$primary" worktree unlock "$wt" || die 70 "could not unlock $wt"; fi
  fi
  sim_pool delete "$name" || exit
  if [ -n "$reg" ]; then
    dir=$evidence/down-$(date +%Y%m%d-%H%M%S)
    saved=$(save_lane "$dir")
    echo "lane.sh: saved $(printf '%s\n' "$saved" | tr '\n' ' ')to $dir" >&2
    git -C "$primary" worktree remove --force "$wt" >&2 || die 70 "git worktree remove $wt failed"
    echo "lane.sh: removed the worktree $wt" >&2
  elif [ -e "$wt" ]; then
    twin=$(case_twin)
    if [ -n "$twin" ]; then
      echo "lane.sh: left $wt alone: it is the directory $twin, because this disk ignores case" >&2
    else
      echo "lane.sh: left $wt alone, because git does not list it as a worktree" >&2
    fi
  fi
  while IFS= read -r d; do
    rm -rf "$d"
    removed=$((removed + 1))
  done < <(derived_data_of "$wt/WorkoutTracker.xcodeproj")
  [ "$removed" -eq 0 ] || echo "lane.sh: removed $removed DerivedData dir(s)" >&2
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
