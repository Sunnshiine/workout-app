# shellcheck shell=bash

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
settings=${SETTINGS:-$repo/.claude/settings.json}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sim-mcp-hook.XXXXXX") || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

LEASED=(boot_sim open_sim build_sim build_run_sim test_sim install_app_sim launch_app_sim)
REFUSED=(erase_sims clean build_device build_run_device test_device build_macos build_run_macos test_macos
    swift_package_build swift_package_run swift_package_test xcode_ide_call_tool session_use_defaults_profile)

FREE=(screenshot snapshot_ui tap swipe type_text long_press gesture button key_press record_sim_video list_sims
    stop_app_sim session_show_defaults session_clear_defaults get_sim_app_path list_schemes)
RECORDERS=(session_set_defaults session_clear_defaults session_use_defaults_profile)

# The hook command and matcher of settings.json's $1 entry that runs scripts/sim-mcp-hook.py.
read_hook() {
    python3 -c '
import json, sys
for entry in json.load(open(sys.argv[1])).get("hooks", {}).get(sys.argv[2], []):
    for h in entry["hooks"]:
        if "sim-mcp-hook.py" in h.get("command", ""):
            print(entry.get("matcher", "")); print(h["command"]); sys.exit()
' "$settings" "$1"
}

# Exits 0 when Claude Code's matcher $1 selects tool $2, which it tests as an unanchored regex.
selects() { python3 -c 'import re, sys; sys.exit(not re.search(sys.argv[1], sys.argv[2]))' "$1" "mcp__XcodeBuildMCP__$2"; }

{ read -r pre_matcher; read -r pre_hook; } < <(read_hook PreToolUse)
{ read -r post_matcher; read -r post_hook; } < <(read_hook PostToolUse)
if [ -z "${pre_hook:-}" ] || [ -z "${post_hook:-}" ]; then
    bad "settings.json runs scripts/sim-mcp-hook.py on PreToolUse and PostToolUse"
    printf '%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi

stub=$tmp/bin
mkdir -p "$stub" "$tmp/nosimlock" "$tmp/state/sim-hook"
cat >"$stub/simlock" <<'STUB'
#!/bin/bash
case ${SIMLOCK_MODE:-} in
    slow) sleep 5 & echo $! >>"$SIMLOCK_FIXTURE/children"; wait; exit 0 ;;
    rendezvous) meet "${2#--}" ;;
    together)
        touch "$SIMLOCK_FIXTURE/started$2"
        other=--devices; [ "$2" = --devices ] && other=--leases
        for _ in $(seq 40); do [ -e "$SIMLOCK_FIXTURE/started$other" ] && break; sleep 0.1; done
        [ -e "$SIMLOCK_FIXTURE/started$other" ] || exit 71 ;;
    garbage) echo 'not json'; exit 0 ;;
    broken) exit 70 ;;
esac
case $2 in
    --leases) cat "$SIMLOCK_FIXTURE/leases" ;;
    --devices) cat "$SIMLOCK_FIXTURE/devices" ;;
esac
STUB
cat >"$tmp/meet.sh" <<'MEET'
# Marks lookup $1 started, then waits up to 4 s for every name in $RENDEZVOUS; exits 71 when one never starts.
meet() {
    touch "$SIMLOCK_FIXTURE/started--$1"
    for _ in $(seq 40); do
        all=1
        for name in $RENDEZVOUS; do [ -e "$SIMLOCK_FIXTURE/started--$name" ] || all=; done
        [ -n "$all" ] && return 0
        sleep 0.1
    done
    exit 71
}
MEET
sed -i.bak "1a\\
. \"$tmp/meet.sh\"
" "$stub/simlock" && rm -f "$stub/simlock.bak"
cat >"$stub/hostgate" <<'STUB'
#!/bin/bash
. "$SIMLOCK_FIXTURE/meet.sh"
echo "$*" >>"$SIMLOCK_FIXTURE/hostgate.calls"
case ${HOSTGATE_MODE:-fine} in
    fine) exit 0 ;;
    stuck) echo '[{"id": "sandbox-report", "severity": "fail"}]'; exit 1 ;;
    broken) exit 70 ;;
    slow) sleep 30 & echo $! >>"$SIMLOCK_FIXTURE/children"; wait ;;
    rendezvous) meet sandbox ;;
esac
STUB
chmod +x "$stub/simlock" "$stub/hostgate"
export SIMLOCK_FIXTURE=$tmp
future=$(( $(date +%s) * 1000 + 3600000 ))
cat >"$tmp/devices" <<'JSON'
[{"id": "dev_mine", "driverDeviceId": "AAAAAAAA-0000-0000-0000-000000000001"},
 {"id": "dev_other", "driverDeviceId": "BBBBBBBB-0000-0000-0000-000000000002"},
 {"id": "dev_anon", "driverDeviceId": "CCCCCCCC-0000-0000-0000-000000000003"},
 {"id": "dev_codex", "driverDeviceId": "FFFFFFFF-0000-0000-0000-000000000006"},
 {"id": "dev_expired", "driverDeviceId": "DDDDDDDD-0000-0000-0000-000000000004"},
 {"id": "dev_free", "driverDeviceId": "EEEEEEEE-0000-0000-0000-000000000005"}]
JSON
cat >"$tmp/leases" <<JSON
[{"id": "lse_mine", "deviceId": "dev_mine", "requesterId": "claude-code:me", "ttlDeadline": $future},
 {"id": "lse_other", "deviceId": "dev_other", "requesterId": "claude-code:someone-else", "ttlDeadline": $future},
 {"id": "lse_anon", "deviceId": "dev_anon", "requesterId": "ci-runner", "ttlDeadline": $future},
 {"id": "lse_codex", "deviceId": "dev_codex", "requesterId": "codex:019a-other-agent", "ttlDeadline": $future},
 {"id": "lse_expired", "deviceId": "dev_expired", "requesterId": "claude-code:me", "ttlDeadline": 1000}]
JSON
MINE=AAAAAAAA-0000-0000-0000-000000000001
OTHER=BBBBBBBB-0000-0000-0000-000000000002
ANON=CCCCCCCC-0000-0000-0000-000000000003
CODEX=FFFFFFFF-0000-0000-0000-000000000006
EXPIRED=DDDDDDDD-0000-0000-0000-000000000004
FREE_UDID=EEEEEEEE-0000-0000-0000-000000000005
log=$tmp/state/sim-hook/workout-app.log

# Runs hook command $1 as Claude Code does for event $2, tool $3, input JSON $4 and session $5, with
# simlock on PATH unless PATH_BIN says otherwise. Sets status; stderr lands in $tmp/err, stdout in $tmp/out.
run() {
    EVENT=$2 TOOL=$3 INPUT=$4 SESSION=${5-me} python3 -c '
import json, os
print(json.dumps({"session_id": os.environ["SESSION"], "hook_event_name": os.environ["EVENT"],
                  "tool_name": "mcp__XcodeBuildMCP__" + os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["INPUT"]), "cwd": "."}))' >"$tmp/in"
    (cd "$repo" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR="$repo" XDG_STATE_HOME="$tmp/state" \
        PATH="${PATH_BIN:-$stub}:/usr/bin:/bin" bash -c "$1" <"$tmp/in" >"$tmp/out" 2>"$tmp/err")
    status=$?
}
gate() { run "$pre_hook" PreToolUse "$@"; }
recorded() { run "$post_hook" PostToolUse "$@"; }
err_has() { grep -qF -- "$1" "$tmp/err"; }
loud() { python3 -c 'import json, sys; sys.exit(sys.argv[2] not in json.loads(sys.argv[1])["systemMessage"])' "$1" "$2" 2>/dev/null; }
# Exits 0 once no pid listed in file $1 runs, within 2 s; a zombie awaiting its reaper counts as ended.
none_alive() {
    local pid tries=20
    while read -r pid; do
        while case $(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ') in '' | Z*) false ;; esac; do
            tries=$((tries - 1)); [ "$tries" -gt 0 ] || return 1; sleep 0.1
        done
    done <"$1"
}

# Sets the session record to UDID $1 for session ${2-me}, as the PostToolUse half does after session_set_defaults.
recorded_as() { recorded session_set_defaults "{\"simulatorId\": \"$1\"}" "${2-me}"; }

setting() { gate session_set_defaults "{\"simulatorId\": \"$1\"}" "${2-me}"; }
