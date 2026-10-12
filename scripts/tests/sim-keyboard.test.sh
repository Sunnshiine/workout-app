#!/bin/bash
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sim-keyboard.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
sim=KEYBOARD-TEST-SIM
plist=$root/home/Library/Developer/CoreSimulator/Devices/$sim/data/Library/Preferences/com.apple.keyboard.preferences.plist
mkdir -p "$root/bin"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# simctl reads the device state from a file, logs every state change, and answers an in-simulator
# defaults read from the plist, as cfprefsd does after a boot. STUB_STUCK pins that read at 1.
cat >"$root/bin/xcrun" <<'STUB'
#!/bin/sh
shift
case $1 in
    list) echo "{\"devices\":{\"iOS-27-0\":[{\"udid\":\"KEYBOARD-TEST-SIM\",\"state\":\"$(cat "$STUB_STATE")\"}]}}" ;;
    spawn)
        [ -z "${STUB_STUCK:-}" ] || { echo 1; exit; }
        value=$(plutil -extract "$6" raw "$STUB_PLIST" 2>/dev/null) || exit 1
        [ "$value" = true ] && echo 1 || echo 0
        ;;
    shutdown) echo "$*" >>"$STUB_CALLS"; echo Shutdown >"$STUB_STATE" ;;
    boot) echo "$*" >>"$STUB_CALLS"; echo Booted >"$STUB_STATE" ;;
    bootstatus) echo "$*" >>"$STUB_CALLS" ;;
esac
STUB
chmod +x "$root/bin/xcrun"

keyboard() {
    rm -f "$root/calls"
    STUB_STATE=$root/state STUB_CALLS=$root/calls STUB_PLIST=$plist HOME=$root/home PATH="$root/bin:$PATH" \
        "$script" "$@" >"$root/out" 2>"$root/err"
    status=$?
}
device() {
    echo "$1" >"$root/state"
    rm -rf "${root:?}/home"
    [ $# = 1 ] || { mkdir -p "$(dirname "$plist")" && plutil -create xml1 "$plist" && shift && plutil -insert AutomaticMinimizationEnabled -bool "$1" "$plist"; }
}
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}
calls() { cat "$root/calls" 2>/dev/null; }
seconds() { sed -E 's/ in [0-9]+ s$/ in N s/' "$root/out"; }

device Booted true
keyboard ensure "$sim"
expect "a booted simulator that minimizes the keyboard is shut down, written, and booted again" \
    "$status
$(seconds)
$(calls)
$(plutil -extract AutomaticMinimizationEnabled raw "$plist") $(plutil -extract HardwareKeyboardLastSeen raw "$plist")" \
    "0
keyboard: $sim had AutomaticMinimizationEnabled=1 HardwareKeyboardLastSeen=unset, set AutomaticMinimizationEnabled=0 HardwareKeyboardLastSeen=0 and rebooted it in N s
shutdown $sim
boot $sim
bootstatus $sim -b
false false"

keyboard ensure "$sim"
expect "a second ensure finds it ready and touches nothing" "$status $(cat "$root/out") $(calls)" \
    "0 keyboard: $sim has AutomaticMinimizationEnabled=0 HardwareKeyboardLastSeen=0 "

device Shutdown
keyboard ensure "$sim"
expect "a shut-down simulator with no preferences file gets one and stays shut down" \
    "$status $(cat "$root/out") $(calls) $(cat "$root/state") $(plutil -extract HardwareKeyboardLastSeen raw "$plist")" \
    "0 keyboard: $sim had AutomaticMinimizationEnabled=unset HardwareKeyboardLastSeen=unset, set AutomaticMinimizationEnabled=0 HardwareKeyboardLastSeen=0  Shutdown false"

device Booted true
STUB_STUCK=1 keyboard ensure "$sim"
expect "a write that does not read back exits 70 and names the script" "$status $(cat "$root/err")" \
    "70 keyboard: wrote $plist but $sim reads AutomaticMinimizationEnabled=1 HardwareKeyboardLastSeen=1; scripts/sim-keyboard.sh no longer sticks (#700)"

device Booting
keyboard ensure "$sim"
expect "a simulator mid-boot is refused untouched" "$status $(cat "$root/err") $(calls)" \
    "69 keyboard: $sim is Booting, not Booted or Shutdown "

device Booted false
keyboard read "$sim"
expect "read prints the pairs and fails while one is unset" "$status $(cat "$root/out") $(calls)" \
    "1 AutomaticMinimizationEnabled=0 HardwareKeyboardLastSeen=unset "

keyboard ensure "$(echo "$sim" | tr '[:upper:]' '[:lower:]')"
keyboard read "$sim"
expect "read passes once ensure has run, given a lower-case UDID" "$status $(cat "$root/out")" \
    "0 AutomaticMinimizationEnabled=0 HardwareKeyboardLastSeen=0"

keyboard ensure
expect "a missing UDID prints usage and exits 2" "$status $(head -1 "$root/err")" \
    "2 Usage: scripts/sim-keyboard.sh read|ensure <UDID>"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
