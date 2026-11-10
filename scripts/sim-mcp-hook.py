#!/usr/bin/env python3
"""Usage: scripts/sim-mcp-hook.py < hook-JSON
A Claude Code hook, for .claude/settings.json, on the XcodeBuildMCP tools that boot, build, test,
install or launch. Agents need a simulator to see what they build, and every simulator here
comes from a Simlock lease (ADR-0024), so these tools run only on a simulator the caller's lease
holds. The target is the call's simulatorId, else the UDID this session last gave
session_set_defaults, which the PostToolUse half records. A refusal names the lease command and the
shell path; the settings hook turns exit 3 into Claude Code's blocking exit 2. When Simlock cannot
answer (missing, slower than SIM_HOOK_TIMEOUT seconds, unreadable output) the call is allowed with a
warning. Each allowed build appends a line to $XDG_STATE_HOME/sim-hook/workout-app.log, because an
MCP build takes no host-wide build slot. Tools that never need a simulator from this server stay
refused, each naming this repo's command. Any argument prints this and exits 2.
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SERVER = "mcp__XcodeBuildMCP__"
REPO = "workout-app"
VERIFY = ".agents/skills/verify/verify.sh"
LEASE = (
    "simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --timeout 540s --detach --ttl 60m"
    " | python3 -c 'import json, sys; g = json.loads(sys.stdin.readline());"
    " print(g[\"device\"][\"driverDeviceId\"], g[\"lease\"][\"id\"])'"
)

ON_LEASE = {"boot_sim", "open_sim", "build_sim", "build_run_sim", "test_sim", "install_app_sim", "launch_app_sim"}
BUILDS = {"build_sim", "build_run_sim", "test_sim"}
REFUSED = {
    "erase_sims": "Simulators here are never erased. simlock release <lease-id> gives yours back, and Simlock resets it.",
    "clean": "Clean in the shell: xcodebuild clean -project WorkoutTracker.xcodeproj -scheme WorkoutTracker",
    "build_device": "The app reaches a phone through TestFlight: add the testflight label to the PR (docs/agents/prototyping.md). On a simulator, use build_run_sim with the simulatorId of your Simlock lease.",
    "build_run_device": "The app reaches a phone through TestFlight: add the testflight label to the PR (docs/agents/prototyping.md). On a simulator, use build_run_sim with the simulatorId of your Simlock lease.",
    "test_device": "Tests run on a leased simulator: scripts/test-sim.sh unit (see its --help).",
    "build_macos": "The app has no macOS target. The macOS build is the workout CLI: scripts/build-slot.sh swift build --product workout",
    "build_run_macos": "The app has no macOS target. The macOS build is the workout CLI: scripts/build-slot.sh swift build --product workout",
    "test_macos": "The app has no macOS target. The macOS tests run as scripts/build-slot.sh swift test",
    "swift_package_build": "Build in a host build slot: scripts/build-slot.sh swift build",
    "swift_package_run": "Run in a host build slot: scripts/build-slot.sh swift run workout <args>",
    "swift_package_test": "Test in a host build slot: scripts/build-slot.sh swift test",
    "xcode_ide_call_tool": "It drives Xcode.app, which takes no build slot and no lease. Use build_run_sim with the simulatorId of your Simlock lease, or the verify skill.",
}
DROPS_RECORD = {"simulatorId", "simulatorName"}
SESSION_TOOLS = {"session_set_defaults", "session_clear_defaults", "session_use_defaults_profile"}


class Unchecked(Exception):
    """Simlock could not say which simulators are leased."""


def state_dir():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "sim-hook"


def record_path(session):
    return state_dir() / f"{REPO}.sessions" / re.sub(r"[^A-Za-z0-9_.-]", "_", session or "unknown")


def recorded_udid(session):
    try:
        return record_path(session).read_text().strip().upper() or None
    except OSError:
        return None


def record(tool, tool_input, session):
    """PostToolUse on the session tools: keep the simulatorId this session set, forget it otherwise."""
    path = record_path(session)
    udid = tool_input.get("simulatorId") if tool == "session_set_defaults" else None
    if udid:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(udid.upper() + "\n")
        return
    keys = set(tool_input.get("keys") or [])
    clears = tool == "session_use_defaults_profile" or (
        tool == "session_clear_defaults" and (tool_input.get("all") or not keys or keys & DROPS_RECORD)
    ) or (tool == "session_set_defaults" and "simulatorName" in tool_input)
    if clears:
        path.unlink(missing_ok=True)


def leases(bound):
    """{UDID: (lease id, requester)} for every live lease, read from Simlock within bound seconds."""
    try:
        runs = {what: subprocess.Popen(["simlock", "list", f"--{what}"], stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, text=True)
                for what in ("leases", "devices")}
    except OSError as error:
        raise Unchecked(f"simlock did not start ({error})")
    deadline, out = time.monotonic() + bound, {}
    try:
        for what, run in runs.items():
            try:
                out[what], _ = run.communicate(timeout=max(0.0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                raise Unchecked(f"simlock list took longer than {bound:g} s")
            if run.returncode:
                raise Unchecked(f"simlock list --{what} exited {run.returncode}")
    finally:
        for run in runs.values():
            if run.poll() is None:
                run.kill()
    try:
        udids = {d["id"]: d["driverDeviceId"].upper() for d in json.loads(out["devices"]) if d.get("driverDeviceId")}
        now = time.time() * 1000
        return {udids[l["deviceId"]]: (l["id"], l.get("requesterId") or "")
                for l in json.loads(out["leases"])
                if l["deviceId"] in udids and l.get("ttlDeadline", now + 1) > now}
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise Unchecked(f"simlock list printed what this hook cannot read ({error!r})")


def callers(session):
    ids = {os.environ.get("CLAUDE_CODE_SESSION_ID"), session}
    return {f"claude-code:{i}" for i in ids if i}


def mine(requester, me):
    """True when the lease is the caller's, or when Simlock's requester cannot say whose it is."""
    return not me or not requester.startswith("claude-code:") or requester in me


def refusal(tool, target, own, me, other):
    lines = [f"Refused: {tool} runs only on a simulator your Simlock lease holds (ADR-0024),"]
    if target is None:
        lines.append("and this call names none: pass simulatorId, or set it with session_set_defaults.")
    elif other:
        lines.append(f"and {target} is leased by {other}, another agent (you are {' or '.join(sorted(me))}).")
    else:
        lines.append(f"and no live Simlock lease holds {target}.")
    if own:
        udid, lease = own
        lines += [
            f"You hold Simlock lease {lease} on {udid}. Call {tool} again with simulatorId: \"{udid}\",",
            f"or call session_set_defaults with simulatorId: \"{udid}\" once and then {tool}.",
        ]
    else:
        lines += [
            "1. Lease one. It waits up to 9 min for a free simulator, so give the shell 600 s, and prints the UDID and the lease id:",
            f"   {LEASE}",
            f"2. Call {tool} again with simulatorId: \"<UDID>\", or session_set_defaults with simulatorId: \"<UDID>\" first.",
            "   The lease lasts 60 min: renew it with simlock lease renew <lease-id>, and give it back with simlock release <lease-id>.",
        ]
    lines += [
        "Or take the shell path, which leases, builds in a host build slot, installs and launches, and prints the UDID",
        "that screenshot, snapshot_ui and touch (down and up; tap reaches no control here) take:",
        f"   {VERIFY} build && {VERIFY} launch session",
    ]
    return "\n".join(lines)


def log_build(tool, session, udid, lease):
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    path = state_dir() / f"{REPO}.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as log:
        log.write(f"{stamp}\t{session}\t{tool}\t{udid}\t{lease}\n")


def gate(tool, tool_input, session):
    """(exit status, stderr text, stdout JSON or None) for a PreToolUse call."""
    if tool in REFUSED:
        return 3, f"Refused: {tool} is off in this repo. {REFUSED[tool]}", None
    if tool not in ON_LEASE:
        return 0, "", None
    target = tool_input.get("simulatorId")
    target = target.upper() if target else None if "simulatorName" in tool_input else recorded_udid(session)
    try:
        held_by = leases(float(os.environ.get("SIM_HOOK_TIMEOUT", "3")))
    except Unchecked as why:
        warning = f"sim-mcp-hook: allowed {tool} on {target or 'the session default'} unchecked, because {why}. Lease your simulator with simlock lease all the same."
        if tool in BUILDS:
            log_build(tool, session, target or "-", "unchecked")
        return 0, warning, {"systemMessage": warning}
    me = callers(session)
    lease, requester = held_by.get(target, (None, ""))
    if lease and mine(requester, me):
        if tool in BUILDS:
            log_build(tool, session, target, lease)
        return 0, "", None
    own = next(((u, l) for u, (l, r) in held_by.items() if me and r in me), None)
    return 3, refusal(tool, target, own, me, requester if lease else None), None


def main():
    if len(sys.argv) > 1:
        sys.stderr.write(__doc__)
        return 2
    try:
        event = json.load(sys.stdin)
        tool = event["tool_name"]
        tool_input = event.get("tool_input") or {}
        session = event.get("session_id") or ""
    except (ValueError, KeyError, TypeError):
        return 0
    if not tool.startswith(SERVER):
        return 0
    tool = tool[len(SERVER):]
    if event.get("hook_event_name") == "PostToolUse":
        if tool in SESSION_TOOLS:
            record(tool, tool_input, session)
        return 0
    status, text, out = gate(tool, tool_input, session)
    if text:
        print(text, file=sys.stderr)
    if out:
        print(json.dumps(out))
    return status


if __name__ == "__main__":
    sys.exit(main())
