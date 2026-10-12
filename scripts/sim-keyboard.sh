#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/sim-keyboard.sh read|ensure <UDID>
  read    prints AutomaticMinimizationEnabled=<0|1|unset> from the simulator's
          com.apple.keyboard.preferences, and exits 1 when it is 1: the simulator then hides the
          software keyboard below the window and the keyboard UI tests fail.
  ensure  sets it to 0 when it reads 1 and prints one `keyboard:` line. The next app launch shows
          the software keyboard; no reboot is needed. Exits 70 when the write does not read back.
An AXe key or type event into a focused text field sets it back to 1, so a verify session can leave
it wrong. scripts/test-sim.sh runs ensure before every selection that includes WorkoutTrackerUITests
(#700).
EOF
  exit 2
}

domain=com.apple.keyboard.preferences
key=AutomaticMinimizationEnabled

device_state() {
  xcrun simctl list devices -j | UDID="$1" python3 -c '
import json, os, sys
print(next((d["state"] for ds in json.load(sys.stdin)["devices"].values() for d in ds
            if d["udid"] == os.environ["UDID"]), "missing"))'
}

plist() { echo "$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/$domain.plist"; }

# The plist lags a booted simulator's cfprefsd by seconds, so a booted simulator is read inside it.
read_key() {
  local value
  case $2 in
    Booted) value=$(xcrun simctl spawn "$1" defaults read "$domain" "$key" 2>/dev/null) || value="unset" ;;
    Shutdown) value=$(plutil -extract "$key" raw "$(plist "$1")" 2>/dev/null) || value="unset" ;;
    *) echo "keyboard: $1 is $2, not Booted or Shutdown" >&2; exit 69 ;;
  esac
  case $value in true | 1) echo 1 ;; false | 0) echo 0 ;; *) echo unset ;; esac
}

write_key() {
  if [ "$2" = Booted ]; then
    xcrun simctl spawn "$1" defaults write "$domain" "$key" -bool false
  else
    plutil -replace "$key" -bool false "$(plist "$1")"
  fi
}

[ $# = 2 ] && { [ "$1" = read ] || [ "$1" = ensure ]; } || usage
sim=$(printf %s "$2" | tr '[:lower:]' '[:upper:]')
state=$(device_state "$sim")
before=$(read_key "$sim" "$state")
case $1 in
  read)
    echo "$key=$before"
    [ "$before" != 1 ]
    ;;
  ensure)
    if [ "$before" != 1 ]; then
      echo "keyboard: $sim has $key=$before"
      exit
    fi
    write_key "$sim" "$state"
    after=$(read_key "$sim" "$state")
    [ "$after" = 0 ] || { echo "keyboard: wrote $key=0 on $sim but it reads $after (#700)" >&2; exit 70; }
    echo "keyboard: $sim had $key=1, set it to 0"
    ;;
esac
