#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/sim-keyboard.sh read|ensure <UDID>
  read    prints the simulator's keyboard preferences as KEY=VALUE pairs (0, 1, or unset) and exits 0
          when every one is 0, the state the keyboard UI tests need, else 1.
  ensure  puts the preferences in that state and prints one `keyboard:` line. When they were wrong
          it shuts the simulator down, writes its preferences plist, and boots it again if it was
          booted. Exits 70 when the write does not read back.
The caller holds the simulator (claim_sim in scripts/sim-lock.sh): ensure may reboot it.
scripts/test-sim.sh runs ensure before every selection that includes WorkoutTrackerUITests (#700).
EOF
  exit 2
}

domain=com.apple.keyboard.preferences
keys="AutomaticMinimizationEnabled HardwareKeyboardLastSeen"

device_state() {
  xcrun simctl list devices -j | UDID="$1" python3 -c '
import json, os, sys
print(next((d["state"] for ds in json.load(sys.stdin)["devices"].values() for d in ds
            if d["udid"] == os.environ["UDID"]), "missing"))'
}

plist() { echo "$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/$domain.plist"; }

# A booted simulator's cfprefsd can hold a value its plist does not show yet, so read inside it.
read_key() {
  local value
  if [ "$2" = Booted ]; then
    value=$(xcrun simctl spawn "$1" defaults read "$domain" "$3" 2>/dev/null) || value="unset"
  else
    value=$(plutil -extract "$3" raw "$(plist "$1")" 2>/dev/null) || value="unset"
  fi
  case $value in true | 1) echo 1 ;; false | 0) echo 0 ;; *) echo unset ;; esac
}

read_prefs() {
  local key pairs=
  for key in $keys; do pairs="$pairs $key=$(read_key "$1" "$2" "$key")"; done
  echo "${pairs# }"
}

ready() { case " $1 " in *=1\ * | *=unset\ *) return 1 ;; esac; }

# A defaults write inside a booted simulator does not survive its reboot; the plist written while
# it is shut down does.
write_prefs() {
  local file key
  file=$(plist "$1")
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$file"
  for key in $keys; do plutil -replace "$key" -bool false "$file"; done
}

ensure() {
  local state before after start note=
  state=$(device_state "$1")
  [ "$state" = Booted ] || [ "$state" = Shutdown ] || { echo "keyboard: $1 is $state, not Booted or Shutdown" >&2; exit 69; }
  before=$(read_prefs "$1" "$state")
  if ready "$before"; then
    echo "keyboard: $1 has $before"
    return
  fi
  start=$(date +%s)
  [ "$state" = Shutdown ] || xcrun simctl shutdown "$1"
  write_prefs "$1"
  if [ "$state" = Booted ]; then
    xcrun simctl boot "$1"
    xcrun simctl bootstatus "$1" -b > /dev/null
    note=" and rebooted it in $(($(date +%s) - start)) s"
  fi
  after=$(read_prefs "$1" "$state")
  ready "$after" || { echo "keyboard: wrote $(plist "$1") but $1 reads $after; scripts/sim-keyboard.sh no longer sticks (#700)" >&2; exit 70; }
  echo "keyboard: $1 had $before, set $after$note"
}

[ $# = 2 ] || usage
sim=$(printf %s "$2" | tr '[:lower:]' '[:upper:]')
case $1 in
  read)
    prefs=$(read_prefs "$sim" "$(device_state "$sim")")
    echo "$prefs"
    ready "$prefs"
    ;;
  ensure) ensure "$sim" ;;
  *) usage ;;
esac
