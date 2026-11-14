# shellcheck shell=bash
# Signals a saved pid only while it is still the process that was started. Pids recycle in minutes on a
# busy Mac, and bash reaps a background job as soon as it exits, so a bare kill of a saved $! can reach
# another agent's process. Read a stamp at launch, then signal through it:
#   pid=$!; stamp=$(proc_stamp "$pid")
#   signal_same TERM "$pid" "$stamp"
# A stamp is read in the C locale, so it compares equal whatever locale the caller or a helper runs in.

# Prints PID's start time (ps lstart), or nothing when no process has that pid.
proc_stamp() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | LC_ALL=C sed 's/^ *//;s/ *$//'; }

# True while PID still started at STAMP and has not exited. An empty STAMP, a launch whose stamp was
# never read, is false, with one line on stderr.
same_process() {
  local stat now
  [ -n "${2:-}" ] || { echo "same_process: no start time on record for pid $1, so it is not taken for the process started" >&2; return 1; }
  IFS=' ' read -r stat now < <(LC_ALL=C ps -o stat= -o lstart= -p "$1" 2>/dev/null) || return 1
  [ "${stat#Z}" = "$stat" ] && [ "$(LC_ALL=C sed 's/ *$//' <<< "$now")" = "$2" ]
}

# signal_same SIG PID STAMP: sends SIG to PID only while same_process holds; else returns 3.
signal_same() {
  same_process "$2" "$3" || return 3
  kill -"$1" "$2" 2>/dev/null
}
