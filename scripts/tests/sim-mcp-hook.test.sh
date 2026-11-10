#!/bin/bash
set -uo pipefail

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

echo "settings.json names the simulator tools through the hook, not a bare deny"
deny=$(python3 -c 'import json, sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"]["deny"]))' "$settings")
for tool in "${LEASED[@]}" "${REFUSED[@]}"; do
    check "no bare deny on $tool" '! grep -qxF "mcp__XcodeBuildMCP__$tool" <<<"$deny"'
done
check "no deny entry on any XcodeBuildMCP tool" '! grep -q "^mcp__XcodeBuildMCP__" <<<"$deny"'
{ read -r pre_matcher; read -r pre_hook; } < <(read_hook PreToolUse)
{ read -r post_matcher; read -r post_hook; } < <(read_hook PostToolUse)
if [ -z "${pre_hook:-}" ] || [ -z "${post_hook:-}" ]; then
    bad "settings.json runs scripts/sim-mcp-hook.py on PreToolUse and PostToolUse"
    printf '%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi
deadline=$(sed -n 's/.*SIM_HOOK_TIMEOUT", "\([0-9.]*\)".*/\1/p' "$repo/scripts/sim-mcp-hook.py")
hook_timeout=$(python3 -c '
import json, sys
for entry in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]:
    for h in entry["hooks"]:
        if "sim-mcp-hook.py" in h.get("command", ""):
            print(h.get("timeout", 60))' "$settings")
check "the PreToolUse timeout (${hook_timeout:-none} s) leaves 5 s past the Simlock deadline (${deadline:-none} s)" \
    'python3 -c "import sys; sys.exit(not float(sys.argv[1]) >= float(sys.argv[2]) + 5)" "$hook_timeout" "$deadline"'
for tool in "${LEASED[@]}" "${REFUSED[@]}" session_set_defaults; do check "PreToolUse hooks $tool" 'selects "$pre_matcher" "$tool"'; done
for tool in "${FREE[@]}"; do check "PreToolUse leaves $tool alone" '! selects "$pre_matcher" "$tool"'; done
for tool in "${RECORDERS[@]}"; do check "PostToolUse records $tool" 'selects "$post_matcher" "$tool"'; done
check "PostToolUse leaves build_run_sim alone" '! selects "$post_matcher" build_run_sim'
check ".mcp.json still names the server XcodeBuildMCP, which the matchers key on" \
    'python3 -c "import json, sys; sys.exit(\"XcodeBuildMCP\" not in json.load(open(sys.argv[1]))[\"mcpServers\"])" "$repo/.mcp.json"'

stub=$tmp/bin
mkdir -p "$stub" "$tmp/nosimlock" "$tmp/state"
cat >"$stub/simlock" <<'STUB'
#!/bin/bash
case ${SIMLOCK_MODE:-} in
    slow) sleep 5 ;;
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
chmod +x "$stub/simlock"
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

echo "a simulator the caller's lease holds runs; any other is refused with the fix"
for tool in "${LEASED[@]}"; do
    gate "$tool" "{\"simulatorId\": \"$MINE\"}"
    check "$tool on the caller's leased simulator runs" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'
done
gate build_run_sim "{\"simulatorId\": \"$(tr '[:upper:]' '[:lower:]' <<<"$MINE")\"}"
check "a lowercase UDID of the caller's lease runs" '[ $status = 0 ]'
gate build_run_sim "{\"simulatorId\": \"$ANON\"}"
check "a lease whose requester is no <agent>:<id> runs" '[ $status = 0 ]'
gate build_run_sim "{\"simulatorId\": \"$CODEX\"}"
check "another agent's lease under another agent's name is refused, naming it" \
    '[ $status = 2 ] && err_has "$CODEX is leased by codex:019a-other-agent, another agent"'

gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}" nobody
check "an unleased simulator is refused" '[ $status = 2 ]'
check "the refusal names the UDID" 'err_has "no live Simlock lease holds $FREE_UDID"'
check "the refusal names the lease command" "err_has \"simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --timeout 540s --detach --ttl 60m\""
check "the refusal says to set the leased UDID as the session default" 'err_has "2. Call session_set_defaults {simulatorId: \"<UDID>\"} alone, then build_run_sim again."'
check "the refusal names the shell path" 'err_has ".agents/skills/verify/verify.sh build && .agents/skills/verify/verify.sh launch session"'
check "the refusal prefers touch and says tap can miss" 'err_has "prefer touch with down and up; tap can miss" && ! err_has "reaches no control"'
check "the refusal never says to pass simulatorId to a tool, which takes none here" '! grep -qiE "pass simulatorId|as simulatorId|simulatorId to" "$tmp/err"'
lease_line=$(grep -F 'simlock lease --platform' "$tmp/err" | sed 's/^ *//')
check "the printed lease command parses as shell" 'bash -n -c "$lease_line"'
grant='{"device": {"driverDeviceId": "U"}, "lease": {"id": "L"}}'
check "the printed lease command reads the UDID and the lease id from a grant" \
    '[ "$(printf "%s\n" "$grant" | bash -c "${lease_line#*| }")" = "U L" ]'

gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "a caller holding a lease is pointed at its own simulator" \
    '[ $status = 2 ] && err_has "You hold Simlock lease lse_mine on $MINE" && err_has "simulatorId: \"$MINE\"" && ! err_has "1. Lease one"'
gate build_run_sim "{\"simulatorId\": \"$OTHER\"}"
check "another agent's leased simulator is refused, naming its holder" \
    '[ $status = 2 ] && err_has "$OTHER is leased by claude-code:someone-else, another agent"'
gate build_run_sim "{\"simulatorId\": \"$EXPIRED\"}"
check "a lease past its deadline is refused" '[ $status = 2 ]'
gate build_run_sim '{"simulatorName": "iPhone 17 Pro"}'
check "a simulator named by model is refused" '[ $status = 2 ] && err_has "this session has none: set it with session_set_defaults {simulatorId}"'

echo "a call without simulatorId uses the UDID the session gave session_set_defaults"
gate build_run_sim '{}'
check "nothing recorded: refused" '[ $status = 2 ] && err_has "this session has none: set it with session_set_defaults {simulatorId}"'
recorded session_set_defaults "{\"simulatorId\": \"$MINE\", \"scheme\": \"WorkoutTracker\"}"
check "the recorder exits 0" '[ $status = 0 ]'
gate build_run_sim '{}'
check "the recorded leased UDID runs" '[ $status = 0 ]'
gate build_run_sim '{}' someone-else
check "another session's record does not carry over" '[ $status = 2 ] && err_has "this session has none: set it with session_set_defaults {simulatorId}"'
recorded session_clear_defaults '{"keys": ["scheme"]}'
gate build_run_sim '{}'
check "clearing another key keeps the record" '[ $status = 0 ]'
recorded session_clear_defaults '{"keys": ["simulatorId"]}'
gate build_run_sim '{}'
check "clearing simulatorId drops the record" '[ $status = 2 ]'
recorded session_set_defaults "{\"simulatorId\": \"$MINE\"}"
recorded session_set_defaults '{"simulatorName": "iPhone 17 Pro"}'
gate build_run_sim '{}'
check "setting simulatorName drops the record" '[ $status = 2 ]'
recorded session_set_defaults "{\"simulatorId\": \"$MINE\", \"simulatorName\": \"iPhone 17 Pro\"}"
gate build_run_sim '{}'
check "an id with a name records nothing, since the server re-resolves the name" '[ $status = 2 ]'
recorded session_set_defaults "{\"simulatorId\": \"$MINE\"}"
recorded session_set_defaults '{"profile": "other"}'
gate build_run_sim '{}'
check "switching profile drops the record" '[ $status = 2 ]'
recorded session_set_defaults "{\"simulatorId\": \"$FREE_UDID\"}"
gate build_run_sim '{}'
check "a recorded unleased UDID is refused" '[ $status = 2 ] && err_has "no live Simlock lease holds $FREE_UDID"'

echo "session defaults name a simulator only by the UDID of a lease"
gate session_set_defaults "{\"simulatorId\": \"$MINE\", \"scheme\": \"WorkoutTracker\"}"
check "session_set_defaults with simulatorId runs" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'
for call in "{\"simulatorId\": \"$MINE\", \"simulatorName\": \"iPhone 17 Pro\"}" '{"simulatorName": "iPhone 17 Pro"}' \
    '{"profile": "wa1220-p4"}' '{"profile": "p", "createIfNotExists": true, "simulatorId": "x"}' \
    "{\"simulatorId\": \"$MINE\", \"persist\": true}"; do
    PATH_BIN=$tmp/nosimlock gate session_set_defaults "$call"
    check "session_set_defaults $call is refused, naming the call that works" \
        '[ $status = 2 ] && err_has "Call session_set_defaults {simulatorId: <your leased UDID>} alone."'
done

echo "the docs point at session_set_defaults and touch"
check "no doc says MCP tap reaches no control" \
    '! grep -rqF "reaches no control here" "$repo/AGENTS.md" "$repo/.agents/skills/verify" "$repo/.agents/skills/simlock"'
check "no doc says to pass the UDID as simulatorId to a tool" \
    '! grep -rqE "take(s)? that UDID as .?simulatorId|as .simulatorId. to" "$repo/AGENTS.md" "$repo/.agents/skills/verify/SKILL.md" "$repo/.agents/skills/simlock/SKILL.md"'
check "the verify skill says tap after session_set_defaults needs a fresh snapshot_ui" \
    'grep -qF SNAPSHOT_EXPIRED "$repo/.agents/skills/verify/SKILL.md"'

dd=$(sed -n 's/^ *derivedDataPath: *//p' "$repo/.xcodebuildmcp/config.yaml")
check "MCP builds keep DerivedData in the worktree, git-ignored, off the internal disk" \
    '[ -n "$dd" ] && [ "${dd#/}" = "$dd" ] && git -C "$repo" check-ignore -q "$dd/x"'

echo "every allowed build is logged; nothing else is"
: >"$log"
gate build_run_sim "{\"simulatorId\": \"$MINE\"}"
gate test_sim "{\"simulatorId\": \"$MINE\"}"
gate launch_app_sim "{\"simulatorId\": \"$MINE\"}"
gate build_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "two allowed builds, two lines" '[ "$(wc -l <"$log" | tr -d " ")" = 2 ]'
check "a line holds time, session, tool, UDID and lease" \
    'head -1 "$log" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z	me	build_run_sim	$MINE	lse_mine$"'

echo "the tools that need no simulator from this server stay refused, each naming a command"
for tool in "${REFUSED[@]}"; do
    gate "$tool" "{\"simulatorId\": \"$MINE\"}"
    check "$tool is refused with a reason" '[ $status = 2 ] && err_has "Refused: $tool is off in this repo." && grep -qE "scripts/|xcodebuild|simlock|testflight|verify skill|session_set_defaults \{simulatorId" "$tmp/err"'
done

echo "when Simlock cannot answer, the call runs with a warning"
: >"$log"
PATH_BIN=$tmp/nosimlock gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "simlock missing: allowed" '[ $status = 0 ] && err_has "unchecked, because simlock did not start"'
check "simlock missing: the warning reaches Claude Code as a systemMessage" \
    'python3 -c "import json, sys; sys.exit(\"unchecked\" not in json.load(open(sys.argv[1]))[\"systemMessage\"])" "$tmp/out"'
check "simlock missing: the build is logged as unchecked" 'grep -q "build_run_sim	$FREE_UDID	unchecked$" "$log"'
SIMLOCK_MODE=slow SIM_HOOK_TIMEOUT=0.3 gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "simlock slower than the bound: allowed" '[ $status = 0 ] && err_has "took longer than 0.3 s"'
rm -f "$tmp"/started--*
SIMLOCK_MODE=together SIM_HOOK_TIMEOUT=6 gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "the device and lease lookups run at once, so neither waits out the other" '[ $status = 2 ] && ! err_has unchecked'
SIMLOCK_MODE=garbage gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "simlock output unreadable: allowed" '[ $status = 0 ] && err_has "cannot read"'
SIMLOCK_MODE=broken gate build_run_sim "{\"simulatorId\": \"$FREE_UDID\"}"
check "simlock failing: allowed" '[ $status = 0 ] && err_has "exited 70"'

echo "the wrapper never blocks on a broken guard"
out=$(echo 'not json' | CLAUDE_PROJECT_DIR=$repo bash -c "$pre_hook" 2>&1; echo "exit=$?")
check "malformed stdin allows silently" '[ "$out" = exit=0 ]'
loud() { python3 -c 'import json, sys; sys.exit(sys.argv[2] not in json.loads(sys.argv[1])["systemMessage"])' "$1" "$2" 2>/dev/null; }
out=$(echo '{}' | CLAUDE_PROJECT_DIR=$tmp/nowhere bash -c "$pre_hook"); status=$?
check "a missing guard allows" '[ $status = 0 ]'
check "a missing guard says so in a systemMessage" 'loud "$out" "sim-mcp-hook.py is missing, so this XcodeBuildMCP call runs without its Simlock lease check"'
mkdir -p "$tmp/crash/scripts" && printf 'raise RuntimeError("boom")\n' >"$tmp/crash/scripts/sim-mcp-hook.py"
out=$(echo '{}' | CLAUDE_PROJECT_DIR=$tmp/crash bash -c "$pre_hook" 2>/dev/null); status=$?
check "a guard that raises allows" '[ $status = 0 ]'
check "a guard that raises says so in a systemMessage" 'loud "$out" "the lease check exited 1, so this XcodeBuildMCP call runs unchecked"'
out=$(python3 "$repo/scripts/sim-mcp-hook.py" --help 2>/dev/null; echo "exit=$?")
check "an argument exits 2" '[ "$out" = exit=2 ]'

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
