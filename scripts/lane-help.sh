# shellcheck shell=bash
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
          or tag holds, and a copy of each results dir under .build that scripts/build-dirs.sh
          lists, .build/verify without its node_modules);
          then remove the worktree and its DerivedData. Each step skips what is already gone, so a
          second down exits 0. --if-idle removes only when assess says remove.
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
and Xcode's helpers orphaned to launchd, such as ibtoold and DTServiceHub, do not count), or another
up or down of the same lane held it for WORKOUT_ADMIT_WAIT seconds (default 540).
EOF
}
