#!/bin/bash
set -uo pipefail

help() {
  cat <<'EOF'
Usage: scripts/reap.sh <run> [pid...]
       scripts/reap.sh --start <run> <command> [arg...]
       scripts/reap.sh --record <run> <pid>...
Ends only processes a run started, so one agent never kills another agent's process by pid number.
A run is a name that matches ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$, scoped to the checkout this script
belongs to, so a run of the same name in another worktree is another run. Its pidfile is
$WORKOUT_RUN_DIR/<checkout>-<checksum>/<run>.pids (/tmp/workout-runs), one row per process: the pid
and its start time in UTC.
  --start   starts the command in its own process group, in the background with its output sent to
            /dev/null, records it, and prints its pid. Start each load process this way, as in
            scripts/reap.sh --start my-run yes.
  --record  records processes the caller started. Exits 1, recording nothing, if a pid is not running
            or is not the caller's child.
  <run>     sends SIGTERM to each recorded process, or only to the named pids, then drops their rows
            and deletes the pidfile once it is empty. A process that leads its own process group, as
            --start makes it, gets the signal with its whole group. A row whose pid now belongs to a
            process that started at another time is dropped and not killed.
Exits 1, killing nothing, when the run has no pidfile or a named pid is not in it.
EOF
}

die() { echo "reap.sh: $2" >&2; exit "$1"; }

case ${1:-} in
  -h | --help) help; exit 0 ;;
  --start | --record) mode=${1#--}; shift ;;
  '') help >&2; exit 2 ;;
  *) mode=reap ;;
esac
[ $# -ge 1 ] || { help >&2; exit 2; }
run=$1
shift
[[ $run =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die 2 "run name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$: $run"
checkout=$(cd "$(dirname "$0")/.." && pwd)
dir=${WORKOUT_RUN_DIR:-/tmp/workout-runs}/${checkout##*/}-$(printf %s "$checkout" | cksum | cut -d ' ' -f 1)
pidfile=$dir/$run.pids

started_at() { TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }

terminate() {
  local target=$1
  [ "$(ps -o pgid= -p "$1" | tr -d ' ')" != "$1" ] || target=-$1
  kill -- "$target" 2>/dev/null
}

record() {
  local parent=$1 pid when rows=
  shift
  for pid in "$@"; do
    [[ $pid =~ ^[1-9][0-9]*$ ]] || die 2 "not a pid: $pid"
    when=$(started_at "$pid")
    [ -n "$when" ] || die 1 "pid $pid is not running, so run $run cannot record it"
    [ "$(ps -o ppid= -p "$pid" | tr -d ' ')" = "$parent" ] \
      || die 1 "pid $pid is not a child of pid $parent, which asked to record it, so run $run cannot record it"
    rows+=$(printf '%s\t%s' "$pid" "$when")$'\n'
  done
  mkdir -p "$dir" || exit 1
  printf '%s' "$rows" >>"$pidfile"
}

case $mode in
  start)
    [ $# -ge 1 ] || { help >&2; exit 2; }
    set -m
    "$@" </dev/null >/dev/null 2>&1 &
    set +m
    record $$ $!
    echo $!
    exit 0 ;;
  record)
    [ $# -ge 1 ] || { help >&2; exit 2; }
    record "$PPID" "$@"
    exit 0 ;;
esac

[ -f "$pidfile" ] || die 1 "run $run has no pidfile at $pidfile, so there is nothing of its own to reap; killed nothing"
for pid in "$@"; do
  awk -F '\t' -v p="$pid" '$1 == p { found = 1 } END { exit !found }' "$pidfile" \
    || die 1 "pid $pid is not in run $run's pidfile ($pidfile), so it is another run's or nobody's; killed nothing"
done

keep=$(mktemp "$pidfile.XXXXXX") || exit 1
while IFS=$'\t' read -r pid when; do
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$pid"; then
    printf '%s\t%s\n' "$pid" "$when" >>"$keep"
  elif [ "$(started_at "$pid")" != "$when" ]; then
    echo "pid $pid already ended"
  elif terminate "$pid"; then
    echo "killed pid $pid"
  else
    echo "pid $pid already ended"
  fi
done <"$pidfile"
if [ -s "$keep" ]; then mv "$keep" "$pidfile"; else rm -f "$keep" "$pidfile"; fi
