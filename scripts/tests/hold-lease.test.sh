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
unset SIM WORKOUT_LEASE_MODE $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$script_dir/../sim-lock.sh")
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
expect "holding none, a call that takes one leases a slim device for 60 min and names its mode" \
    "$? $out | $(log_since "$before") | $(tail -1 "$root/err")" \
    "0 $first | lease lse_1 $first by verifier, detached, mode slim, ttl 60m | simulator $first (Simlock lease lse_1, slim); verify.sh release gives it back"

reset; before=0
out=$(FAKE_SIMLOCK_GRANT_MODE=full hold "" take)
expect "the line it prints names the mode Simlock granted, not the one it asked for" \
    "$? $out | $(log_since "$before") | $(tail -1 "$root/err")" \
    "0 $first | lease lse_1 $first by verifier, detached, mode full, ttl 60m | simulator $first (Simlock lease lse_1, full); verify.sh release gives it back"

reset; before=0
out=$(WORKOUT_LEASE_MODE=full hold "" take)
expect "with WORKOUT_LEASE_MODE=full it leases a full device" \
    "$? $out | $(log_since "$before")" "0 $first | lease lse_1 $first by verifier, detached, mode full, ttl 60m"

reset; lease 60m slim; before=$(mark)
out=$(WORKOUT_LEASE_MODE=full hold "" take)
expect "asking for full over a held slim lease exits 2, naming the release, and leases and releases nothing" \
    "$? $out | $(log_since "$before") | $(cat "$root/err")" \
    "2  |  | your Simlock lease lse_1 on $first is slim, and this verify call asks for a full one (WORKOUT_LEASE_MODE=full); give it back with simlock release lse_1 and rerun, or run on it with WORKOUT_LEASE_MODE=slim"
out=$(WORKOUT_LEASE_MODE=full hold "")
expect "a call that takes no lease, as a drive, stop or release, runs on the slim lease" "$? $out" "0 $first"

reset; lease 60m full; before=$(mark)
out=$(hold "" take)
expect "a held full lease serves the slim default as it is" "$? $out | $(log_since "$before")" "0 $first | "

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
