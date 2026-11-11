#!/usr/bin/env bash
# hold_lease, the lease every verify.sh call resolves its simulator through.
set -uo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
first=HOLD-LEASE-A-$$
second=HOLD-LEASE-B-$$
cleanup() {
    rm -rf "$root" "/tmp/workout-verify-$first" "/tmp/workout-verify-$second"
}
trap cleanup EXIT
mkdir -p "$root/bin"
cp "$script_dir/fake-simlock" "$root/bin/simlock"
chmod +x "$root/bin/simlock"
export PATH="$root/bin:$PATH" FAKE_SIMLOCK_STATE=$root/simlock FAKE_SIMLOCK_DEVICES="$first $second" FAKE_SIMLOCK_WHO=verifier
export WORKOUT_HOST_LOCK_DIR=$root/locks TMPDIR=$root
# shellcheck disable=SC2046
unset SIM $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$script_dir/../sim-lock.sh")
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi; }

hold() { ( sim=; . "$script_dir/../sim-lock.sh"; hold_lease "$@"; echo "$sim" ) 2>"$root/err"; }
lease() { simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --detach --ttl "$1" --mode "$2" >/dev/null; }
reset() { rm -rf "$FAKE_SIMLOCK_STATE"; }
mark() { wc -l <"$FAKE_SIMLOCK_STATE/log" | tr -d ' '; }
log_since() { tail -n +$(($1 + 1)) "$FAKE_SIMLOCK_STATE/log" | grep -E '^(lease|release|renew)'; }
ttl_ms() { simlock list --leases | python3 -c 'import json, sys; print(" ".join(str(l["ttlMs"]) for l in json.load(sys.stdin)))'; }

reset; lease 10m full; before=$(mark)
out=$(hold "" take)
expect "on a held full lease of 10 min it renews that lease with a 60 min TTL and leases nothing" \
    "$? $out | $(log_since "$before") | $(ttl_ms)" "0 $first | renew lse_1, ttl 60m | 3600000"

reset; lease 60m full; before=$(mark)
out=$(hold "" take)
expect "on a fresh 60 min full lease it changes nothing" "$? $out | $(log_since "$before")" "0 $first | "

reset; lease 120m full; before=$(mark)
out=$(hold "" take)
expect "a longer lease is never shortened" "$? $out | $(log_since "$before") | $(ttl_ms)" "0 $first |  | 7200000"

reset; lease 10m slim; before=$(mark)
out=$(hold "" take)
expect "a lease the caller took elsewhere, slim included, is used as it is: never released or swapped" \
    "$? $out | $(log_since "$before")" "0 $first | renew lse_1, ttl 60m"

reset; before=0
out=$(hold "" take)
expect "holding none, a call that takes one leases a full device for 60 min" \
    "$? $out | $(log_since "$before")" "0 $first | lease lse_1 $first by verifier, detached, mode full, ttl 60m"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
