#!/bin/bash
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sim-keyboard.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
sim=KEYBOARD-TEST-SIM
plist=$root/home/Library/Developer/CoreSimulator/Devices/$sim/data/Library/Preferences/com.apple.keyboard.preferences.plist
mkdir -p "$root/bin" "$(dirname "$plist")"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# The booted simulator's defaults live in $STUB_DEFAULTS, a file holding the value or nothing.
# STUB_STUCK makes a write inside the simulator do nothing. Every call that writes is logged.
cat >"$root/bin/xcrun" <<'STUB'
#!/bin/sh
shift
case $1 in
    list) echo "{\"devices\":{\"iOS-27-0\":[{\"udid\":\"KEYBOARD-TEST-SIM\",\"state\":\"$STUB_STATE\"}]}}" ;;
    spawn)
        case $4 in
            read) [ -s "$STUB_DEFAULTS" ] && cat "$STUB_DEFAULTS" || { echo "does not exist" >&2; exit 1; } ;;
            write)
                echo "$*" >>"$STUB_CALLS"
                [ -n "${STUB_STUCK:-}" ] || echo 0 >"$STUB_DEFAULTS"
                ;;
        esac
        ;;
    *) echo "$*" >>"$STUB_CALLS" ;;
esac
STUB
chmod +x "$root/bin/xcrun"

keyboard() {
    rm -f "$root/calls"
    STUB_STATE=$state STUB_DEFAULTS=$root/defaults STUB_CALLS=$root/calls HOME=$root/home PATH="$root/bin:$PATH" \
        "$script" "$@" >"$root/out" 2>"$root/err"
    status=$?
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

state=Booted
echo 1 >"$root/defaults"
keyboard ensure "$sim"
expect "a booted simulator that hides the keyboard gets the key written inside it, with no reboot" \
    "$status $(cat "$root/out") | $(calls) | $(cat "$root/defaults")" \
    "0 keyboard: $sim had AutomaticMinimizationEnabled=1, set it to 0 | spawn $sim defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false | 0"

keyboard ensure "$sim"
expect "a second ensure finds it at 0 and writes nothing" "$status $(cat "$root/out") | $(calls)" \
    "0 keyboard: $sim has AutomaticMinimizationEnabled=0 | "

: >"$root/defaults"
keyboard ensure "$sim"
expect "an absent key passes the keyboard tests, so ensure leaves it" "$status $(cat "$root/out") | $(calls)" \
    "0 keyboard: $sim has AutomaticMinimizationEnabled=unset | "

echo 1 >"$root/defaults"
STUB_STUCK=1 keyboard ensure "$sim"
expect "a write that does not read back exits 70" "$status $(cat "$root/err")" \
    "70 keyboard: wrote AutomaticMinimizationEnabled=0 on $sim but it reads 1 (#700)"

state=Shutdown
plutil -create xml1 "$plist" && plutil -insert AutomaticMinimizationEnabled -bool true "$plist"
keyboard ensure "$sim"
expect "a shut-down simulator gets its plist written and is not booted" \
    "$status $(cat "$root/out") | $(calls) | $(plutil -extract AutomaticMinimizationEnabled raw "$plist")" \
    "0 keyboard: $sim had AutomaticMinimizationEnabled=1, set it to 0 |  | false"

state=Booting
keyboard ensure "$sim"
expect "a simulator mid-boot is refused untouched" "$status $(cat "$root/err") | $(calls)" \
    "69 keyboard: $sim is Booting, not Booted or Shutdown | "

state=Booted
echo 1 >"$root/defaults"
keyboard read "$(echo "$sim" | tr '[:upper:]' '[:lower:]')"
expect "read prints the value and fails at 1, given a lower-case UDID" "$status $(cat "$root/out") | $(calls)" \
    "1 AutomaticMinimizationEnabled=1 | "

echo 0 >"$root/defaults"
keyboard read "$sim"
expect "read passes at 0" "$status $(cat "$root/out")" "0 AutomaticMinimizationEnabled=0"

keyboard reset "$sim"
expect "an unknown verb prints usage and exits 2" "$status $(head -1 "$root/err")" \
    "2 Usage: scripts/sim-keyboard.sh read|ensure <UDID>"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
