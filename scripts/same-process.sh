# shellcheck shell=bash
# Signals a saved pid only while it is still the process that was started. Pids recycle in minutes on a
# busy Mac, and bash reaps a background job as soon as it exits, so a bare kill of a saved $! can reach
# another agent's process. Read a stamp at launch, then signal through it:
#   pid=$!; stamp=$(proc_stamp "$pid")
#   signal_same TERM "$pid" "$stamp"

# Prints PID's start time (ps lstart), or nothing when no process has that pid.
proc_stamp() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }

# True while PID still started at STAMP and has not exited.
same_process() {
  local stat now
  [ -n "${2:-}" ] || return 1
  read -r stat now < <(ps -o stat= -o lstart= -p "$1" 2>/dev/null) || return 1
  [ "${stat#Z}" = "$stat" ] && [ "$(sed 's/ *$//' <<< "$now")" = "$2" ]
}

# signal_same SIG PID STAMP: sends SIG to PID only while same_process holds; else returns 3.
signal_same() {
  same_process "$2" "$3" || return 3
  kill -"$1" "$2" 2>/dev/null
}
