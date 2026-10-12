#!/bin/bash
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sim-keyboard.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
sim=KEYBOARD-TEST-SIM
mkdir -p "$root/bin"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/xcrun" <<'STUB'
#!/bin/sh
shift
case "$1 $4" in
    "bootstatus ")
        echo "$*" >>"$STUB_CALLS"
        [ -z "${STUB_BOOT_FAILS:-}" ] || { echo "Invalid device: $2" >&2; exit 148; }
        ;;
    "spawn read")
        [ -z "${STUB_READ_FAILS:-}" ] || { echo "Process spawn via launchd failed (code=405)" >&2; exit 1; }
        [ -s "$STUB_DEFAULTS" ] && cat "$STUB_DEFAULTS" || { echo "Error: Could not find key '$6' in domain '$5'." >&2; exit 1; }
        ;;
    "spawn write")
        echo "$*" >>"$STUB_CALLS"
        [ -n "${STUB_WRITE_IGNORED:-}" ] || echo 0 >"$STUB_DEFAULTS"
        ;;
    *) echo "$*" >>"$STUB_CALLS" ;;
esac
STUB
chmod +x "$root/bin/xcrun"

keyboard() {
    rm -f "$root/calls"
    STUB_DEFAULTS=$root/defaults STUB_CALLS=$root/calls PATH="$root/bin:$PATH" "$script" "$@" >"$root/out" 2>"$root/err"
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

echo 1 >"$root/defaults"
keyboard ensure "$(echo "$sim" | tr '[:upper:]' '[:lower:]')"
expect "a simulator that hides the keyboard gets the key written inside it, after its boot, with no reboot" \
    "$status $(cat "$root/out") | $(calls) | $(cat "$root/defaults")" \
    "0 keyboard: $sim had AutomaticMinimizationEnabled=1, set it to 0 | bootstatus $sim -b
spawn $sim defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false | 0"

keyboard ensure "$sim"
expect "a second ensure finds it at 0 and writes nothing" "$status $(cat "$root/out") | $(calls)" \
    "0 keyboard: $sim has AutomaticMinimizationEnabled=0 | bootstatus $sim -b"

: >"$root/defaults"
keyboard ensure "$sim"
expect "an absent key passes the keyboard tests, so ensure leaves it" "$status $(cat "$root/out")" \
    "0 keyboard: $sim has AutomaticMinimizationEnabled=unset"

echo 1 >"$root/defaults"
STUB_WRITE_IGNORED=1 keyboard ensure "$sim"
expect "a write that does not read back exits 70" "$status $(cat "$root/err")" \
    "70 keyboard: wrote AutomaticMinimizationEnabled=0 on $sim but it reads 1 (#700)"

STUB_READ_FAILS=1 keyboard ensure "$sim"
expect "a read that fails for another reason than a missing key exits 69 and writes nothing" \
    "$status $(cat "$root/err") | $(calls)" \
    "69 keyboard: cannot read AutomaticMinimizationEnabled on $sim: Process spawn via launchd failed (code=405) | bootstatus $sim -b"

STUB_BOOT_FAILS=1 keyboard ensure "$sim"
expect "a simulator simctl cannot boot exits 69 and reads nothing" "$status $(cat "$root/err") | $(calls)" \
    "69 Invalid device: $sim
keyboard: cannot boot $sim | bootstatus $sim -b"

keyboard read "$sim"
expect "anything but ensure prints usage and exits 2" "$status $(head -1 "$root/err")" \
    "2 Usage: scripts/sim-keyboard.sh ensure <UDID>"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
