#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/sim-mcp-hook-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/sim-mcp-hook-harness.sh"
# shellcheck source=scripts/same-process.sh
. "$repo/scripts/same-process.sh"

echo "when Simlock cannot answer, the call runs with a warning"
: >"$log"
recorded_as "$FREE_UDID"
PATH_BIN=$tmp/nosimlock gate build_run_sim '{}'
check "simlock missing: allowed" '[ $status = 0 ] && err_has "unchecked, because simlock did not start"'
check "simlock missing: the warning reaches Claude Code as a systemMessage" \
    'python3 -c "import json, sys; sys.exit(\"unchecked\" not in json.load(open(sys.argv[1]))[\"systemMessage\"])" "$tmp/out"'
check "simlock missing: the build is logged as unchecked" 'grep -q "build_run_sim	$FREE_UDID	unchecked$" "$log"'
PATH_BIN=$tmp/nosimlock gate session_set_defaults "{\"simulatorId\": \"$FREE_UDID\"}"
check "simlock missing: session_set_defaults with a simulatorId runs, saying so" \
    '[ $status = 0 ] && err_has "allowed session_set_defaults on $FREE_UDID unchecked, because simlock did not start"'
SIMLOCK_MODE=slow SIM_HOOK_TIMEOUT=0.3 gate session_set_defaults "{\"simulatorId\": \"$FREE_UDID\"}"
check "simlock slower than the bound: session_set_defaults with a simulatorId runs, saying so" \
    '[ $status = 0 ] && err_has "took longer than 0.3 s"'
SIMLOCK_MODE=slow SIM_HOOK_TIMEOUT=0.3 gate build_run_sim '{}'
check "simlock slower than the bound: allowed" '[ $status = 0 ] && err_has "took longer than 0.3 s"'
rm -f "$tmp"/started--*
SIMLOCK_MODE=together SIM_HOOK_TIMEOUT=6 gate build_run_sim '{}'
check "the device and lease lookups run at once, so neither waits out the other" '[ $status = 2 ] && ! err_has unchecked'
SIMLOCK_MODE=garbage gate build_run_sim '{}'
check "simlock output unreadable: allowed" '[ $status = 0 ] && err_has "cannot read"'
SIMLOCK_MODE=broken gate build_run_sim '{}'
check "simlock failing: allowed" '[ $status = 0 ] && err_has "exited 70"'

echo "before a build, a stuck host sandbox refuses, naming what works without one"
: >"$tmp/hostgate.calls"
recorded_as "$MINE"
for tool in build_sim build_run_sim test_sim; do
    HOSTGATE_MODE=stuck gate "$tool" '{}'
    check "$tool with sandbox reporting stuck is refused" \
        '[ $status = 2 ] && err_has "Refused: host sandbox reporting is stuck, so $tool would hang."'
done
check "the refusal says a later build may get through, and names the operator step that clears it for good" \
    'err_has "The check flaps, so a build a minute later may get through. The operator clears it for good: restart" && err_has "sandboxd when no simulator lease is held, or reboot."'
check "with the default leased, the stuck refusal says nothing of leasing" '! err_has "Those MCP tools run only" && ! err_has "1. Lease one"'
HOSTGATE_MODE=stuck HOSTGATE_DELAY=4.5 gate build_run_sim '{}'
check "a stuck check as slow as the real one (4.5 s) still refuses under the default bound of 12 s" \
    '[ $status = 2 ] && err_has "Refused: host sandbox reporting is stuck"'
check "the refusal says the shell build hangs too" 'err_has "so does the shell route (.agents/skills/verify/verify.sh build)"'
check "the refusal names launching this worktree's build" 'err_has ".agents/skills/verify/verify.sh launch session "'
check "the refusal names launching a cached commit" 'err_has ".agents/skills/verify/verify.sh launch --at <commit> session"'
check "the refusal names seeing and driving it" 'err_has "shot <name>, and tap --id <id>" && err_has "install_app_sim, launch_app_sim, screenshot, snapshot_ui, and touch (down and up)"'
check "the check asked is the sandbox one" 'grep -qx "check --only sandbox-report" "$tmp/hostgate.calls"'
: >"$tmp/hostgate.calls"
for tool in boot_sim open_sim install_app_sim launch_app_sim; do
    HOSTGATE_MODE=stuck gate "$tool" '{}'
    check "$tool, which builds nothing, runs while the sandbox is stuck" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'
done
HOSTGATE_MODE=stuck gate session_set_defaults "{\"simulatorId\": \"$MINE\"}"
check "session_set_defaults runs while the sandbox is stuck" '[ $status = 0 ]'
check "a tool that builds nothing and is allowed asks no hostgate" '[ ! -s "$tmp/hostgate.calls" ]'

echo "under a stuck sandbox, each refusal knows the other state"
recorded_as "$FREE_UDID" nobody
HOSTGATE_MODE=stuck gate build_run_sim '{}' nobody
check "a stuck build with no leased default also says how to lease" \
    '[ $status = 2 ] && err_has "Refused: host sandbox reporting is stuck" && err_has "this session'"'"'s default ($FREE_UDID) is not one:" && err_has "1. Lease one."'
recorded_as "$FREE_UDID"
HOSTGATE_MODE=stuck gate build_run_sim '{}'
check "a stuck build whose caller holds another lease points it there" \
    '[ $status = 2 ] && err_has "You hold Simlock lease lse_mine on $MINE. Call session_set_defaults {simulatorId: \"$MINE\"} alone."'
for tool in install_app_sim launch_app_sim; do
    HOSTGATE_MODE=stuck gate "$tool" '{}' nobody
    check "$tool refused for its lease while the sandbox is stuck offers the shell path with no build" \
        '[ $status = 2 ] && err_has "builds nothing, since host sandbox reporting is stuck" && err_has "   .agents/skills/verify/verify.sh launch session" && ! err_has "verify.sh build"'
done
HOSTGATE_MODE=fine gate install_app_sim '{}' nobody
check "the same refusal with a fine sandbox offers the shell build" \
    '[ $status = 2 ] && err_has ".agents/skills/verify/verify.sh build && .agents/skills/verify/verify.sh launch session"'
recorded_as "$MINE"
HOSTGATE_MODE=fine gate build_run_sim '{}'
check "a fine sandbox lets the build run, quietly" '[ $status = 0 ] && [ ! -s "$tmp/err" ] && [ ! -s "$tmp/out" ]'
mkdir -p "$tmp/simlock-only" && cp "$stub/simlock" "$tmp/simlock-only/"
PATH_BIN=$tmp/simlock-only gate build_run_sim '{}'
check "hostgate missing: the build runs, saying so" \
    '[ $status = 0 ] && err_has "could not check host sandbox reporting before build_run_sim, because hostgate did not start" && loud "$(cat "$tmp/out")" "could not check host sandbox"'
HOSTGATE_MODE=broken gate build_run_sim '{}'
check "hostgate check erroring: the build runs, saying so" '[ $status = 0 ] && err_has "because hostgate check exited 70"'
: >"$tmp/children"
HOSTGATE_MODE=slow SIM_HOOK_SANDBOX_TIMEOUT=0.5 gate build_run_sim '{}'
check "hostgate past its bound: the build runs, saying so" '[ $status = 0 ] && err_has "because hostgate check took longer than 0.5 s"'
check "hostgate past its bound: the check and its children are ended" 'none_alive "$tmp/children"'
HOSTGATE_MODE=stuck gate build_run_sim "{\"simulatorId\": \"$MINE\"}"
check "a build naming a simulator is refused for that first, before any lookup" '[ $status = 2 ] && err_has "takes no simulatorId"'
rm -f "$tmp"/started--*
HOSTGATE_MODE=rendezvous SIMLOCK_MODE=rendezvous RENDEZVOUS="leases devices sandbox" gate build_run_sim '{}'
check "the sandbox check runs at once with the lease lookups" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'

echo "a lookup cut short leaves nothing running"
rm -f "$tmp"/outlived--*
SIMLOCK_MODE=slow SIMLOCK_SLEEP=3 SIM_HOOK_TIMEOUT=0.3 gate build_run_sim '{}'
check "a lookup past its bound is ended with its group, not waited out" \
    '[ $status = 0 ] && [ ! -e "$tmp/outlived--leases" ] && [ ! -e "$tmp/outlived--devices" ]'
: >"$tmp/children"
SIMLOCK_MODE=slow SIM_HOOK_TIMEOUT=0.3 gate build_run_sim '{}'
check "simlock past its bound: the lookups and their children are ended" 'none_alive "$tmp/children"'
: >"$tmp/children"
printf '%s' '{"session_id": "me", "hook_event_name": "PreToolUse", "tool_name": "mcp__XcodeBuildMCP__build_run_sim", "tool_input": {}}' >"$tmp/in"
(cd "$repo" && exec env -u CLAUDE_CODE_SESSION_ID SIMLOCK_MODE=slow HOSTGATE_MODE=slow SIM_HOOK_TIMEOUT=20 \
    SIM_HOOK_SANDBOX_TIMEOUT=20 CLAUDE_PROJECT_DIR="$repo" XDG_STATE_HOME="$tmp/state" PATH="$stub:/usr/bin:/bin" \
    python3 scripts/sim-mcp-hook.py <"$tmp/in" >/dev/null 2>&1) &
hook=$! hook_stamp=$(proc_stamp $!)
for _ in $(seq 40); do [ "$(wc -l <"$tmp/children" | tr -d " ")" -ge 3 ] && break; sleep 0.1; done
signal_same TERM "$hook" "$hook_stamp"; wait "$hook"; hook_status=$?
check "a hook ended by SIGTERM exits 143 and ends every lookup and its children" '[ $hook_status = 143 ] && none_alive "$tmp/children"'
echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
