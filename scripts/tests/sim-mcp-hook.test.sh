#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/sim-mcp-hook-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/sim-mcp-hook-harness.sh"

echo "settings.json names the simulator tools through the hook, not a bare deny"
deny=$(python3 -c 'import json, sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"]["deny"]))' "$settings")
for tool in "${LEASED[@]}" "${REFUSED[@]}"; do
    check "no bare deny on $tool" '! grep -qxF "mcp__XcodeBuildMCP__$tool" <<<"$deny"'
done
check "no deny entry on any XcodeBuildMCP tool" '! grep -q "^mcp__XcodeBuildMCP__" <<<"$deny"'
deadline=$(sed -n 's/.*SIM_HOOK_\(SANDBOX_\)*TIMEOUT", "\([0-9.]*\)".*/\2/p' "$repo/scripts/sim-mcp-hook.py" | sort -n | tail -1)
hook_timeout=$(python3 -c '
import json, sys
for entry in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]:
    for h in entry["hooks"]:
        if "sim-mcp-hook.py" in h.get("command", ""):
            print(h.get("timeout", 60))' "$settings")
check "the PreToolUse timeout (${hook_timeout:-none} s) leaves 5 s past the longest lookup deadline (${deadline:-none} s)" \
    'python3 -c "import sys; sys.exit(not float(sys.argv[1]) >= float(sys.argv[2]) + 5)" "$hook_timeout" "$deadline"'
for tool in "${LEASED[@]}" "${REFUSED[@]}" session_set_defaults; do check "PreToolUse hooks $tool" 'selects "$pre_matcher" "$tool"'; done
for tool in "${FREE[@]}"; do check "PreToolUse leaves $tool alone" '! selects "$pre_matcher" "$tool"'; done
for tool in "${RECORDERS[@]}"; do check "PostToolUse records $tool" 'selects "$post_matcher" "$tool"'; done
check "PostToolUse leaves build_run_sim alone" '! selects "$post_matcher" build_run_sim'
check ".mcp.json still names the server XcodeBuildMCP, which the matchers key on" \
    'python3 -c "import json, sys; sys.exit(\"XcodeBuildMCP\" not in json.load(open(sys.argv[1]))[\"mcpServers\"])" "$repo/.mcp.json"'

echo "session_set_defaults takes only a UDID this session's lease holds"
setting "$MINE"
check "the caller's leased simulator becomes the default" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'
setting "$(tr '[:upper:]' '[:lower:]' <<<"$MINE")"
check "a lowercase UDID of the caller's lease does too" '[ $status = 0 ]'
setting "$ANON"
check "a lease whose requester is no <agent>:<id> does too" '[ $status = 0 ]'
setting "$CODEX"
check "another agent's lease under another agent's name is refused, naming it" \
    '[ $status = 2 ] && err_has "$CODEX is leased by codex:019a-other-agent, another agent"'
setting "$OTHER"
check "another Claude session's leased simulator is refused, naming its holder" \
    '[ $status = 2 ] && err_has "$OTHER is leased by claude-code:someone-else, another agent"'
setting "$EXPIRED"
check "a lease past its deadline is refused" '[ $status = 2 ] && err_has "no live Simlock lease holds $EXPIRED"'
setting "$FREE_UDID" nobody
check "an unleased simulator is refused" '[ $status = 2 ] && err_has "Refused: session_set_defaults sets as the default only a simulator your Simlock lease holds"'
check "the refusal names the UDID" 'err_has "no live Simlock lease holds $FREE_UDID"'
check "the refusal names the lease command" "err_has \"simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --timeout 540s --detach --ttl 60m\""
check "the refusal names the call that works" 'err_has "2. Call session_set_defaults {simulatorId: \"<UDID>\"} alone."'
check "the refusal names the shell path" 'err_has ".agents/skills/verify/verify.sh build && .agents/skills/verify/verify.sh launch session"'
check "the refusal prefers touch and says tap can miss" 'err_has "prefer touch with down and up; tap can miss" && ! err_has "reaches no control"'
check "the refusal never says to pass simulatorId to a tool, which takes none here" '! grep -qiE "pass simulatorId|as simulatorId|simulatorId to" "$tmp/err"'
lease_line=$(grep -F 'simlock lease --platform' "$tmp/err" | sed 's/^ *//')
check "the printed lease command parses as shell" 'bash -n -c "$lease_line"'
grant='{"device": {"driverDeviceId": "U"}, "lease": {"id": "L"}}'
check "the printed lease command reads the UDID and the lease id from a grant" \
    '[ "$(printf "%s\n" "$grant" | bash -c "${lease_line#*| }")" = "U L" ]'
setting "$FREE_UDID"
check "a caller holding a lease is pointed at its own simulator" \
    '[ $status = 2 ] && err_has "You hold Simlock lease lse_mine on $MINE. Call session_set_defaults {simulatorId: \"$MINE\"} alone." && ! err_has "1. Lease one"'
gate session_set_defaults '{"scheme": "WorkoutTracker"}'
check "session_set_defaults without a simulator runs" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'

echo "the leased tools take no simulator here: they run on the session default, which the record names"
for tool in "${LEASED[@]}"; do
    recorded_as "$MINE"
    gate "$tool" '{}'
    check "$tool on the caller's recorded leased simulator runs" '[ $status = 0 ] && [ ! -s "$tmp/err" ]'
    for key in simulatorId simulatorName; do
        gate "$tool" "{\"$key\": \"$MINE\"}"
        check "$tool with $key is refused, naming session_set_defaults" \
            '[ $status = 2 ] && err_has "$tool takes no $key on this server" && err_has "Call session_set_defaults {simulatorId: <your leased UDID>} alone"'
    done
done
recorded_as "$FREE_UDID"
gate build_run_sim "{\"simulatorId\": \"$MINE\"}"
check "a default on an unleased simulator is not cleared by naming the caller's lease in the call" '[ $status = 2 ]'
recorded_as "$FREE_UDID" nobody
gate build_run_sim '{}' nobody
check "a build on a recorded unleased simulator is refused with the lease command" \
    '[ $status = 2 ] && err_has "no live Simlock lease holds" && err_has "2. Call session_set_defaults {simulatorId: \"<UDID>\"} alone, then build_run_sim again."'
recorded_as "$OTHER"
gate build_run_sim '{}'
check "a build on another agent's recorded simulator is refused, naming its holder" \
    '[ $status = 2 ] && err_has "$OTHER is leased by claude-code:someone-else, another agent"'
recorded session_clear_defaults '{}'

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
recorded_as "$MINE"
gate build_run_sim '{}'
gate test_sim '{}'
gate launch_app_sim '{}'
recorded_as "$FREE_UDID"
gate build_sim '{}'

check "two allowed builds, two lines" '[ "$(wc -l <"$log" | tr -d " ")" = 2 ]'
check "a line holds time, session, tool, UDID and lease" \
    'head -1 "$log" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z	me	build_run_sim	$MINE	lse_mine$"'

echo "the tools that need no simulator from this server stay refused, each naming a command"
for tool in "${REFUSED[@]}"; do
    gate "$tool" "{\"simulatorId\": \"$MINE\"}"
    check "$tool is refused with a reason" '[ $status = 2 ] && err_has "Refused: $tool is off in this repo." && grep -qE "scripts/|xcodebuild|simlock|testflight|verify skill|session_set_defaults \{simulatorId" "$tmp/err"'
done

echo "the wrapper never blocks on a broken guard"
out=$(echo 'not json' | CLAUDE_PROJECT_DIR=$repo bash -c "$pre_hook" 2>&1; echo "exit=$?")
check "malformed stdin allows silently" '[ "$out" = exit=0 ]'
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
