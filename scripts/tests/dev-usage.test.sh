#!/bin/bash
set -uo pipefail

dev_usage="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dev-usage.sh"
tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
export WORKOUT_DEV_USAGE_DIR=$tmp/ledger
unset WORKOUT_DEV_USAGE_FAKE_PROCS WORKOUT_DEV_USAGE_LABEL
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }
record() { "$dev_usage" record "$@" >"$tmp/out" 2>"$tmp/err"; }
last_row() { tail -1 "$WORKOUT_DEV_USAGE_DIR/commands.tsv"; }

echo "record"
record t -- sh -c 'echo out; echo err >&2; exit 3'; status=$?
expect "it passes the exit status, stdout, and stderr through, adding nothing" \
    "$status $(cat "$tmp/out") $(cat "$tmp/err")" "3 out err"
expect "it appends one row: ts worktree name exit wall_s cpu_s max_rss_mb sim sim_cpu_s load1" \
    "$(last_row | awk -F '\t' -v top="$(git rev-parse --show-toplevel)" '{ print NF, ($1 ~ /^[0-9]+$/), ($2 == top), $3, $4,
        ($5 ~ /^[0-9.]+$/), ($6 ~ /^[0-9.]+$/), ($7 ~ /^[0-9]+$/), $8, $9, ($10 ~ /^[0-9.]+$/) }')" \
    "10 1 1 t 3 1 1 1 - - 1"
expect "the ledger starts with its header" "$(head -1 "$WORKOUT_DEV_USAGE_DIR/commands.tsv")" \
    "$(printf 'ts\tworktree\tname\texit\twall_s\tcpu_s\tmax_rss_mb\tsim\tsim_cpu_s\tload1')"
printf 'in\n' | "$dev_usage" record t -- cat >"$tmp/out"
expect "it passes stdin through" "$(cat "$tmp/out")" "in"
"$dev_usage" record burn -- sh -c 'sh -c "i=0; while [ \$i -lt 100000 ]; do i=\$((i + 1)); done"'
expect "cpu_s counts a grandchild the command reaped" "$(last_row | awk -F '\t' '{ print ($6 >= 0.05) }')" "1"
(record t -- sh -c 'kill -TERM $$') 2>/dev/null; status=$?
expect "a command killed by a signal kills record with the same signal" "$status $(last_row | cut -f4)" "143 143"
"$dev_usage" record t -- yes 2>"$tmp/err" | head -1 >/dev/null; status=${PIPESTATUS[0]}
expect "a command writing to a closed pipe dies of SIGPIPE, quietly" "$status $(cat "$tmp/err")" "141 "
"$dev_usage" record t -- sh -c 'trap "echo got TERM; exit 7" TERM; touch "$1/ready"; while :; do sleep 0.05; done' _ "$tmp" \
    >"$tmp/out" 2>"$tmp/err" &
recorder=$!
for _ in $(seq 1 100); do [ -f "$tmp/ready" ] && break; sleep 0.05; done
kill -TERM "$recorder"; wait "$recorder"; status=$?
expect "it forwards TERM to the command and exits with the command's status" "$status $(cat "$tmp/out")" "7 got TERM"
record t -- no-such-command-here; status=$?
expect "a command that is not found exits 127 with one line" "$status $(wc -l <"$tmp/err" | tr -d ' ')" "127 1"
WORKOUT_DEV_USAGE_DIR=$tmp/out "$dev_usage" record t -- sh -c 'echo kept; exit 4' >"$tmp/kept" 2>"$tmp/err"; status=$?
expect "a ledger it cannot write leaves the status and output alone, with one line on stderr" \
    "$status $(cat "$tmp/kept") $(wc -l <"$tmp/err" | tr -d ' ') $(cut -d ' ' -f1-4 "$tmp/err")" "4 kept 1 dev-usage: could not append"
record t; status=$?
expect "with no -- it prints the usage and exits 2" "$status $(sed -n 2p "$tmp/err")" \
    "2 Usage: scripts/dev-usage.sh sample | record <name> [--sim UDID] -- <command...>"

echo "sample"
udid=11111111-2222-3333-4444-555555555555
mkdir -p "$tmp/wt/.git" "$tmp/wt/sub" "$tmp/Devices/$udid"
printf '<?xml version="1.0"?>\n<plist version="1.0">\n<dict>\n\t<key>name</key>\n\t<string>workout-lane-a</string>\n</dict>\n</plist>\n' \
    >"$tmp/Devices/$udid/device.plist"
fake() {
    cat >"$tmp/procs.json" <<EOF
{"host": [1000.5, 20000, 1700000000], "procs": {
 "1": {"ppid": 0, "comm": "launchd"},
 "10": {"ppid": 1, "comm": "2.1.303", "argv": ["/u/.local/bin/claude"], "cwd": "$tmp/wt/sub", "cpu": 100, "mb": 500},
 "11": {"ppid": 10, "comm": "zsh", "cpu": 2, "mb": 5},
 "12": {"ppid": 11, "comm": "xcodebuild", "cpu": 40, "mb": 1000},
 "13": {"ppid": 10, "comm": "claude", "argv": ["claude"], "cpu": 3},
 "20": {"ppid": 1, "comm": "codex", "argv": ["/opt/codex"], "cwd": "$tmp/elsewhere", "cpu": 1},
 "30": {"ppid": 1, "comm": "launchd_sim", "argv": ["launchd_sim", "$tmp/Devices/$udid/data/var/run/launchd_bootstrap.plist"], "cpu": 10, "mb": 100},
 "31": {"ppid": 30, "comm": "SpringBoard", "cpu": $1, "mb": 50},
 "40": {"ppid": 1, "comm": "grep", "argv": ["grep", "launchd_sim $tmp/Devices/$udid/"], "cpu": 9},
 "41": {"ppid": 1, "comm": "launchd_sim", "argv": ["launchd_sim"], "cpu": 9},
 "50": {"ppid": 1, "comm": "2.1.0", "argv": ["node", "claude"], "cpu": 9}}}
EOF
}
fake 5
WORKOUT_DEV_USAGE_FAKE_PROCS=$tmp/procs.json "$dev_usage" sample; status=$?
expect "it appends a host row, one row per agent tree, and one per simulator tree, saying nothing" \
    "$status $(tail -n +2 "$WORKOUT_DEV_USAGE_DIR"/samples-*.tsv | cut -f2- | tr '\t\n' ' /')" \
    "0 host host 1700000000 1000.50 20000/agent $tmp/wt 10 145.00 1505/agent $tmp/elsewhere 20 1.00 0/sim workout-lane-a 30 15.00 150/"
cat >"$tmp/bump.sh" <<EOF
#!/bin/bash
$(declare -f fake)
tmp=$tmp udid=$udid fake 12
EOF
WORKOUT_DEV_USAGE_FAKE_PROCS=$tmp/procs.json "$dev_usage" record sim --sim "$udid" -- bash "$tmp/bump.sh"
expect "record --sim records what that simulator's tree used during the command" "$(last_row | cut -f8,9)" "$(printf '%s\t7.00' "$udid")"

echo "report"
now=$(date +%s)
day=$WORKOUT_DEV_USAGE_DIR/samples-$(date -u +%Y-%m-%d).tsv
rm -f "$WORKOUT_DEV_USAGE_DIR"/samples-*.tsv
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$((now - $1))" "$2" "$3" "$4" "$5" "$6" >>"$day"; }
row 10800 host host 9 500 1; row 10800 agent A 100 50 1
row 5400 host host 9 1000 1; row 5400 agent A 100 60 1; row 5400 agent B 300 10 1; row 5400 agent C 500 20 1
row 3600 host host 9 1600 1; row 3600 agent A 100 90 1; row 3600 sim S 400 7 300
row 1800 host host 9 2200 1; row 1800 agent A 200 5 1
row 60 host host 9 2800 1; row 60 agent A 200 25 1; row 60 agent B 300 15 1; row 60 agent C 500 15 1; row 60 sim S 400 10 200
"$dev_usage" report --since 2h >"$tmp/out"; status=$?
expect "per pid, last minus first; a pid that started after an earlier sample counts from 0; a drop counts 0" \
    "$status $(tail -n +3 "$tmp/out" | awk '{ printf "%s %s %s/", $1, $2, $NF }')" \
    "0 host 1800.0 host/agent 55.0 A/agent 5.0 B/agent 0.0 C/sim 10.0 S/rest 1730.0 tree/"
expect "cores divide by the window's span, and peak_mb is the largest sample" "$(grep -E '^(host|sim) ' "$tmp/out" | awk '{ print $3, $5 }' | tr '\n' /)" \
    "0.34 1/0.00 300/"
"$dev_usage" report --since 2h --by sim >"$tmp/out"
expect "--by sim prints only simulators" "$(tail -n +3 "$tmp/out" | awk '{ print $1, $NF }')" "sim S"
cmd() { printf '%s\t/wt\t%s\t%s\t5.00\t%s\t%s\t-\t-\t1.00\n' "$((now - $1))" "$2" "$3" "$4" "$5" >>"$WORKOUT_DEV_USAGE_DIR/commands.tsv"; }
cmd 90000 "swift test" 0 999 999; cmd 60 "swift test" 0 10 100; cmd 50 "swift test" 1 30 300; cmd 40 "swift test" 0 20 200
"$dev_usage" report --by command >"$tmp/out"
expect "--by command prints count, failures, median and p90 CPU s, median wall s, peak RSS per name" \
    "$(grep 'swift test$' "$tmp/out" | awk '{ print $1, $2, $3, $4, $5, $6, $7 }')" "3 1 20.0 30.0 5.0 300 -"
"$dev_usage" report --since 2x 2>"$tmp/err"; status=$?
expect "a window it cannot read exits 2" "$status" "2"

echo "install"
mkdir -p "$tmp/bin" "$tmp/home"
printf '#!/bin/sh\necho "$*" >>"%s/launchctl-calls"\n' "$tmp" >"$tmp/bin/launchctl"
chmod +x "$tmp/bin/launchctl"
installed() { HOME=$tmp/home PATH="$tmp/bin:$PATH" WORKOUT_DEV_USAGE_LABEL=test.dev-usage "$dev_usage" "$@"; }
plist=$tmp/home/Library/LaunchAgents/test.dev-usage.plist
installed install >"$tmp/out"; status=$?
expect "install writes a LaunchAgent that runs the ledger's copy of sample every 60 s" \
    "$status $(plutil -extract ProgramArguments raw -o - "$plist") $(plutil -extract ProgramArguments.3 raw -o - "$plist") $(plutil -extract StartInterval raw -o - "$plist")" \
    "0 5 $WORKOUT_DEV_USAGE_DIR/bin/dev-usage.py 60"
expect "and loads it in the user's launchd domain" "$(tail -1 "$tmp/launchctl-calls")" "bootstrap gui/$(id -u) $plist"
expect "and says what it installed" "$(head -1 "$tmp/out")" "installed the LaunchAgent test.dev-usage: $plist"
installed uninstall >"$tmp/out"; status=$?
expect "uninstall unloads it, deletes it, and keeps the ledger" \
    "$status $(tail -1 "$tmp/launchctl-calls") $([ -e "$plist" ] && echo kept) $([ -f "$WORKOUT_DEV_USAGE_DIR/commands.tsv" ] && echo ledger)" \
    "0 bootout gui/$(id -u)/test.dev-usage  ledger"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
