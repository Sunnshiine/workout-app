#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/sim-keyboard.sh ensure <UDID>
Sets AutomaticMinimizationEnabled in the simulator's com.apple.keyboard.preferences to 0 when it
reads 1 and prints one `keyboard:` line. At 1 the simulator hides the software keyboard below the
window and the keyboard UI tests fail; the next app launch after the write shows it again, with no
reboot. An AXe key or type event into a focused text field sets it back to 1, so a verify session
can leave it wrong. Boots the simulator first if it is not booted. Exits 69 when the simulator
cannot be booted or read and 70 when the write fails or does not read back.
scripts/test-sim.sh runs this before every selection that includes WorkoutTrackerUITests (#700).
EOF
  exit 2
}

domain=com.apple.keyboard.preferences
key=AutomaticMinimizationEnabled

read_key() {
  local value
  value=$(xcrun simctl spawn "$1" defaults read "$domain" "$key" 2>&1) || case $value in
    *"Could not find key"* | *"Domain '$domain' not found"*) value="unset" ;;
    *) echo "keyboard: cannot read $key on $1: $value" >&2; exit 69 ;;
  esac
  case $value in 1) echo 1 ;; 0) echo 0 ;; *) echo unset ;; esac
}

[ $# = 2 ] && [ "$1" = ensure ] || usage
sim=$(printf %s "$2" | tr '[:lower:]' '[:upper:]')
xcrun simctl bootstatus "$sim" -b > /dev/null || { echo "keyboard: cannot boot $sim" >&2; exit 69; }
before=$(read_key "$sim")
if [ "$before" != 1 ]; then
  echo "keyboard: $sim has $key=$before"
  exit
fi
xcrun simctl spawn "$sim" defaults write "$domain" "$key" -bool false \
  || { echo "keyboard: cannot write $key on $sim (#700)" >&2; exit 70; }
after=$(read_key "$sim")
[ "$after" = 0 ] || { echo "keyboard: wrote $key=0 on $sim but it reads $after (#700)" >&2; exit 70; }
echo "keyboard: $sim had $key=1, set it to 0"
