#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/warn-stale-checkout-test.sh
Drives scripts/warn-stale-checkout.sh through every checkout state it has to tell apart and
asserts the stdout it produces, using throwaway repositories under a temporary directory.
It never touches this repository's own checkout.

Each case runs the SessionStart hook command read out of .claude/settings.json, so the matrix
fails if the script is right but the wiring is wrong. Exits 0 only when every case passed.
EOF
  exit 2
}

[ $# -eq 0 ] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/warn-stale-checkout.sh"
SETTINGS="$ROOT/.claude/settings.json"

HOOK_COMMAND=$(python3 -c '
import json, sys
entries = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
commands = [h["command"] for e in entries for h in e["hooks"]]
assert len(commands) == 1, "expected exactly one SessionStart hook, found %d" % len(commands)
print(commands[0])
' "$SETTINGS")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

g() {
  git -c user.name=harness -c user.email=harness@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

commit_to() {
  printf '%s\n' "$2" >"$1/file.txt"
  g -C "$1" add -A
  g -C "$1" commit --quiet -m "$2"
}

install_script() {
  mkdir -p "$1/scripts"
  cp "$SCRIPT" "$1/scripts/warn-stale-checkout.sh"
}

new_fixture() {
  local name=$1
  local up="$WORK/$name/upstream.git"
  local seed="$WORK/$name/seed"
  local n
  FIXTURE="$WORK/$name/checkout"
  mkdir -p "$WORK/$name"
  g init --quiet --bare -b main "$up"
  g init --quiet -b main "$seed"
  commit_to "$seed" base
  g -C "$seed" remote add origin "$up"
  g -C "$seed" push --quiet -u origin main
  g clone --quiet "$up" "$FIXTURE"
  for n in 1 2 3; do commit_to "$seed" "upstream $n"; done
  g -C "$seed" push --quiet origin main
  g -C "$FIXTURE" fetch --quiet origin
  install_script "$FIXTURE"
}

run_hook() {
  local dir=$1
  local project_dir=${2-$1}
  local reason=${3-startup}
  local stdin_json
  if [ -n "$project_dir" ]; then
    export CLAUDE_PROJECT_DIR="$project_dir"
  else
    unset CLAUDE_PROJECT_DIR
  fi
  set +e
  if [ -z "$reason" ]; then
    OUT=$(cd "$dir" && sh -c "$HOOK_COMMAND" </dev/null 2>"$WORK/stderr")
  else
    stdin_json=$(printf '{"session_id":"harness","transcript_path":"/dev/null","cwd":"%s","hook_event_name":"SessionStart","session_start_reason":"%s"}' "$dir" "$reason")
    OUT=$(cd "$dir" && printf '%s' "$stdin_json" | sh -c "$HOOK_COMMAND" 2>"$WORK/stderr")
  fi
  STATUS=$?
  set -e
  unset CLAUDE_PROJECT_DIR
  ERR=$(cat "$WORK/stderr")
}

failures=0
check() {
  local description=$1
  shift
  if "$@"; then
    printf '    ok    %s\n' "$description"
  else
    printf '    FAIL  %s\n' "$description"
    failures=$((failures + 1))
  fi
}

contains() {
  case "$2" in
    *"$1"*) return 0 ;;
    *) return 1 ;;
  esac
}

assert_clean_exit() {
  check "exits 0 (got $STATUS)" test "$STATUS" -eq 0
  check "writes nothing to stderr (got ${#ERR} bytes)" test -z "$ERR"
}

assert_silent() {
  assert_clean_exit
  check "prints nothing (got ${#OUT} bytes)" test -z "$OUT"
}

assert_warns() {
  local needle
  assert_clean_exit
  check "prints a warning" test -n "$OUT"
  for needle in "$@"; do
    check "says \"$needle\"" contains "$needle" "$OUT"
  done
  printf '%s\n' "$OUT" | sed 's/^/    | /'
}

HOOK_EVENTS=$(python3 -c '
import json, sys
print(" ".join(sorted(json.load(open(sys.argv[1]))["hooks"])))
' "$SETTINGS")

echo "hook command under test: $HOOK_COMMAND"
echo

echo "0. the hook is registered on session start and on no per-turn event"
check "registers exactly one hook event, SessionStart (got \"$HOOK_EVENTS\")" \
  test "$HOOK_EVENTS" = SessionStart
echo

echo "1. primary checkout, non-main branch, behind origin/main -> warns, names branch and distance"
new_fixture case1
g -C "$FIXTURE" checkout --quiet -b feature
commit_to "$FIXTURE" "local work"
run_hook "$FIXTURE"
assert_warns "branch     feature" "distance   1 ahead, 3 behind origin/main" \
  "git show origin/main:<path>" "git worktree add"
echo

echo "2. primary checkout, on main, level with origin/main -> silent"
new_fixture case2
g -C "$FIXTURE" merge --quiet --ff-only origin/main
run_hook "$FIXTURE"
assert_silent
echo

echo "3. primary checkout, on main, behind origin/main -> warns"
new_fixture case3
run_hook "$FIXTURE"
assert_warns "branch     main" "distance   0 ahead, 3 behind origin/main"
echo

echo "4. inside a linked worktree -> silent"
new_fixture case4
g -C "$FIXTURE" worktree add --quiet "$FIXTURE/linked" -b linked-branch
install_script "$FIXTURE/linked"
run_hook "$FIXTURE/linked"
assert_silent
echo

echo "5. outside any git repo -> silent, exit 0, no stderr noise"
mkdir -p "$WORK/case5"
install_script "$WORK/case5"
run_hook "$WORK/case5"
assert_silent
echo

echo "6. primary checkout, on main, ahead of origin/main only -> silent"
new_fixture case6
g -C "$FIXTURE" merge --quiet --ff-only origin/main
commit_to "$FIXTURE" "unpushed work"
run_hook "$FIXTURE"
assert_silent
echo

echo "7. primary checkout, detached HEAD behind origin/main -> warns and names the commit"
new_fixture case7
g -C "$FIXTURE" checkout --quiet --detach HEAD
run_hook "$FIXTURE"
assert_warns "detached HEAD at" "distance   0 ahead, 3 behind origin/main"
echo

echo "8. hook command with CLAUDE_PROJECT_DIR unset, cwd at the repo root -> warns"
new_fixture case8
run_hook "$FIXTURE" ""
assert_warns "branch     main" "distance   0 ahead, 3 behind origin/main"
echo

echo "9. upstream repository deleted -> still warns from the last-fetched ref, proving no remote access"
new_fixture case9
rm -rf "$WORK/case9/upstream.git"
run_hook "$FIXTURE"
assert_warns "branch     main" "distance   0 ahead, 3 behind origin/main"
echo

echo "10. primary checkout, non-main branch, level with origin/main -> warns, the issue #610 case"
new_fixture case10
g -C "$FIXTURE" merge --quiet --ff-only origin/main
g -C "$FIXTURE" checkout --quiet -b feature
run_hook "$FIXTURE"
assert_warns "branch     feature" "distance   0 ahead, 0 behind origin/main"
echo

echo "11. a compaction continuing a session that was already warned -> silent"
new_fixture case11
run_hook "$FIXTURE" "$FIXTURE" compact
assert_silent
echo

echo "12. a resume, which opens a fresh context -> warns"
new_fixture case12
run_hook "$FIXTURE" "$FIXTURE" resume
assert_warns "branch     main" "distance   0 ahead, 3 behind origin/main"
echo

echo "13. stdin closed with no hook payload -> warns rather than swallowing the warning"
new_fixture case13
run_hook "$FIXTURE" "$FIXTURE" ""
assert_warns "branch     main" "distance   0 ahead, 3 behind origin/main"
echo

echo "14. the script absent from the checkout -> silent, exit 0, no stderr noise"
new_fixture case14
rm -f "$FIXTURE/scripts/warn-stale-checkout.sh"
run_hook "$FIXTURE"
assert_silent
echo

if [ "$failures" -eq 0 ]; then
  echo "all cases passed"
else
  echo "$failures assertion(s) failed"
  exit 1
fi
