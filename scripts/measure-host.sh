#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/measure-host.sh [--settle SECONDS] [--keep] N <unit|visual|ui|all|TEST-ID>...
Measures how this Mac holds up with N simulators testing at once, as ADR-0020 did. Creates the pool
clones workout-lane-measure-1..N, boots them, waits --settle seconds (default 120, past the CPU a
boot costs, #912), then starts N scripts/test-sim.sh --no-build runs of the selection at once, one
per clone, 2 s apart. The runs reuse this checkout's last build; run scripts/test-sim.sh once first.
The admission gates are lifted for these runs (WORKOUT_SIM_CAP, WORKOUT_MEM_FLOOR=0), since this
measures the host, not admission. Waits up to 5 minutes for the 1-minute load to fall under 10
before it boots anything. Samples every 2 s: the 1-minute load, CPU busy percent, free memory
(kern.memorystatus_level), swap used, and booted simulators. --keep leaves the clones booted;
otherwise they are deleted at the end, and on any exit. The last line is
  measure-host: n=<N> suite=<s> slowest=<s>s failed=<runs>/<N> exit75=<runs> min_free=<p>% max_load=<l> swap_growth_mb=<m> dir=<path>
and .build/measure-host/<stamp>/ holds samples.tsv and each run's output.
Exits 0 when every run passed, 1 when any run failed, 2 on usage, 75 when the host stayed busy.
EOF
  exit 2
}

settle=120
keep=0
while [ $# -gt 0 ]; do
  case $1 in
    --settle) [ $# -ge 2 ] || usage; settle=$2; shift ;;
    --keep) keep=1 ;;
    -h | --help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 2 ] || usage
n=$1
shift
[[ $n =~ ^[1-9][0-9]*$ ]] && [[ $settle =~ ^[0-9]+$ ]] || usage

repo=$(cd "$(dirname "$0")/.." && pwd)
out=$repo/.build/measure-host/$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
udids=()
sampler=

cleanup() {
  [ -z "$sampler" ] || kill "$sampler" 2>/dev/null
  [ $keep = 1 ] && return
  local i
  for i in $(seq 1 "$n"); do "$repo/scripts/sim-pool.sh" delete "measure-$i" 2>/dev/null; done
}
trap cleanup EXIT

sample() {
  printf 'ts\tload1\tcpu_pct\tfree_pct\tswap_mb\tbooted\n' >"$out/samples.tsv"
  while :; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" \
      "$(sysctl -n vm.loadavg | awk '{print $2}')" \
      "$(top -l 2 -n 0 -s 1 | awk '/CPU usage/ {u = $3; s = $5} END {print u + s}')" \
      "$(sysctl -n kern.memorystatus_level)" \
      "$(sysctl -n vm.swapusage | awk '{sub("M", "", $6); print $6}')" \
      "$(xcrun simctl list devices | grep -c '(Booted)')" >>"$out/samples.tsv"
    sleep 1
  done
}

for _ in $(seq 1 30); do
  [ "$(sysctl -n vm.loadavg | awk '{print int($2)}')" -ge 10 ] || break
  sleep 10
done
load=$(sysctl -n vm.loadavg | awk '{print $2}')
awk -v l="$load" 'BEGIN { exit !(l >= 10) }' && { echo "the 1-minute load stayed at $load, over 10, for 5 minutes" >&2; exit 75; }

export WORKOUT_SIM_CAP=999 WORKOUT_MEM_FLOOR=0 WORKOUT_ADMIT_WAIT=1800
for i in $(seq 1 "$n"); do
  udids+=("$("$repo/scripts/sim-pool.sh" create "measure-$i")") || exit 70
done
sample &
sampler=$!
boots=()
for i in $(seq 1 "$n"); do
  "$repo/scripts/sim-pool.sh" boot "measure-$i" >/dev/null &
  boots+=($!)
done
wait "${boots[@]}"
echo "booted $n clones; settling $settle s" >&2
sleep "$settle"

runs=()
for i in $(seq 1 "$n"); do
  (
    start=$(date +%s)
    "$repo/scripts/test-sim.sh" --no-build --sim "${udids[$((i - 1))]}" "$@" >"$out/run-$i.log" 2>&1
    rc=$?
    echo "run=$i rc=$rc wall=$(($(date +%s) - start)) $(tail -1 "$out/run-$i.log")" >>"$out/runs.txt"
  ) &
  runs+=($!)
  sleep 2
done
wait "${runs[@]}"
sleep 4
kill "$sampler" 2>/dev/null
sampler=

cat "$out/runs.txt" >&2
summary=$(awk -v n="$n" '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
    if (v["wall"] > slow) slow = v["wall"]; if (v["rc"] != 0 && v["rc"] != 75) failed++; if (v["rc"] == 75) busy++ }
  END { printf "slowest=%ds failed=%d/%d exit75=%d", slow, failed, n, busy }' "$out/runs.txt")
host=$(awk -F '\t' 'NR > 1 { if (min == "" || $4 < min) min = $4; if ($2 > max) max = $2; if (NR == 2) s0 = $5; s1 = $5 }
  END { printf "min_free=%s%% max_load=%s swap_growth_mb=%d", min, max, s1 - s0 }' "$out/samples.tsv")
selection="$*"
echo "measure-host: n=$n suite=${selection// /,} $summary $host dir=$out"
grep -q 'rc=[1-9]' "$out/runs.txt" && exit 1
exit 0
