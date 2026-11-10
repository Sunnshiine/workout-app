#!/usr/bin/env python3
"""Usage: scripts/sim-mcp-hook.py < hook-JSON
A Claude Code hook, for .claude/settings.json, on the XcodeBuildMCP tools that boot, build, test,
install or launch. Agents need a simulator to see what they build, and every simulator here
comes from a Simlock lease (ADR-0024), so these tools run only on a simulator the caller's lease
holds. None of them takes a simulator on this server: each runs on the session default, so a call
naming simulatorId or simulatorName is refused, and the target is the UDID this session last gave
session_set_defaults, which the PostToolUse half records. session_set_defaults is lease-checked
when it sets that UDID, so the default can only become a simulator this session's lease holds. A
call that names a simulator by name, switches profile or persists would let the server's default
drift from that record, so it is refused, naming session_set_defaults {simulatorId} alone. A refusal names the lease command and the
shell path; the settings hook turns exit 3 into Claude Code's blocking exit 2. When Simlock cannot
answer (missing, slower than SIM_HOOK_TIMEOUT seconds (default 8), unreadable output) the call is allowed with a
warning. Before a build, `hostgate check --only sandbox-report` runs alongside, bounded by SIM_HOOK_SANDBOX_TIMEOUT
(default 12; the check takes about 7 s when reporting is stuck): stuck refuses, since the build would hang, naming
what still works and the operator step; no answer allows with a warning. Each allowed build appends a line to $XDG_STATE_HOME/sim-hook/workout-app.log, because an
MCP build takes no host-wide build slot. Tools that never need a simulator from this server stay
refused, each naming this repo's command. Any argument prints this and exits 2.
"""
import json
import os
import re
import signal
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
    "build_device": "The app reaches a phone through TestFlight: add the testflight label to the PR (docs/agents/prototyping.md). On a simulator, set session_set_defaults {simulatorId: <your leased UDID>}, then build_run_sim.",
    "build_run_device": "The app reaches a phone through TestFlight: add the testflight label to the PR (docs/agents/prototyping.md). On a simulator, set session_set_defaults {simulatorId: <your leased UDID>}, then build_run_sim.",
    "test_device": "Tests run on a leased simulator: scripts/test-sim.sh unit (see its --help).",
    "build_macos": "The app has no macOS target. The macOS build is the workout CLI: scripts/build-slot.sh swift build --product workout",
    "build_run_macos": "The app has no macOS target. The macOS build is the workout CLI: scripts/build-slot.sh swift build --product workout",
    "test_macos": "The app has no macOS target. The macOS tests run as scripts/build-slot.sh swift test",
    "swift_package_build": "Build in a host build slot: scripts/build-slot.sh swift build",
    "swift_package_run": "Run in a host build slot: scripts/build-slot.sh swift run workout <args>",
    "swift_package_test": "Test in a host build slot: scripts/build-slot.sh swift test",
    "xcode_ide_call_tool": "It drives Xcode.app, which takes no build slot and no lease. Set session_set_defaults {simulatorId: <your leased UDID>}, then build_run_sim, or use the verify skill.",
    "session_use_defaults_profile": "A profile can name a simulator no lease holds. Call session_set_defaults {simulatorId: <your leased UDID>} alone.",
}
DROPS_RECORD = {"simulatorId", "simulatorName"}
UNTRACKED = ("simulatorName", "profile", "persist")
AGENT_ID = re.compile(r"[A-Za-z][\w.-]*:\S+")
SANDBOX_CHECK = ["hostgate", "check", "--only", "sandbox-report"]
SANDBOX_STUCK = """Refused: host sandbox reporting is stuck, so {tool} would hang. Every Xcode build of this app runs SwiftLint's
build plug-in, which waits on it, and so does the shell route ({verify} build). hostgate check --only sandbox-report says so.
It needs the operator: restart sandboxd when no simulator lease is held, or reboot. Then build again.
What works now, with an app already built (no build step):
   {verify} launch session                  this worktree's last build
   {verify} launch --at <commit> session    a commit already in the shared app cache (one not cached yet would build)
   {verify} shot <name>, and tap --id <id>  see and drive it
   XcodeBuildMCP install_app_sim, launch_app_sim, screenshot, snapshot_ui, and touch (down and up) on your leased simulator"""
SESSION_TOOLS = {"session_set_defaults", "session_clear_defaults", "session_use_defaults_profile"}


class Unchecked(Exception):
    """Simlock or hostgate could not answer."""


class Interrupted(Exception):
    """A signal ended the hook; raised so the lookups it started are ended too."""


def state_dir():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "sim-hook"


def record_path(session):
    return state_dir() / f"{REPO}.sessions" / re.sub(r"[^A-Za-z0-9_.-]", "_", session or "unknown")


def recorded_udid(session):
    try:
        return record_path(session).read_text().strip().upper() or None
    except OSError:
        return None


def stray_destination(extra_args, udid):
    """The first -destination in a build's extraArgs that names a simulator other than udid ("" when it has no value)."""
    args = extra_args if isinstance(extra_args, list) else []
    for i, arg in enumerate(args):
        if arg != "-destination":
            continue
        spec = str(args[i + 1]) if i + 1 < len(args) else ""
        fields = dict(f.split("=", 1) for f in spec.split(",") if "=" in f)
        if not udid or fields.get("id", "").strip().upper() != udid:
            return spec
    return None


def record(tool, tool_input, session):
    """PostToolUse on the session tools: keep the simulatorId this session set, forget it otherwise."""
    path = record_path(session)
    udid = tool_input.get("simulatorId") if tool == "session_set_defaults" else None
    if tool == "session_set_defaults" and any(k in tool_input for k in UNTRACKED):
        udid = None
    if udid:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(udid.upper() + "\n")
        return
    keys = set(tool_input.get("keys") or [])
    clears = tool == "session_use_defaults_profile" or (
        tool == "session_clear_defaults" and (tool_input.get("all") or not keys or keys & DROPS_RECORD)
    ) or (tool == "session_set_defaults" and any(k in tool_input for k in UNTRACKED))
    if clears:
        path.unlink(missing_ok=True)


def start(argv):
    """Popen in its own process group, so a run cut short can be ended with everything it started."""
    try:
        return subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    except OSError as error:
        return error


def finish(run, deadline):
    """(exit status, stdout); None when it runs past deadline; the OSError when it never started."""
    if isinstance(run, OSError):
        return run
    try:
        out, _ = run.communicate(timeout=max(0.0, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        return None
    return run.returncode, out


def lookups(lease_bound, sandbox_bound):
    """Simlock's live leases, and the host sandbox check when sandbox_bound is set, all started at once.
    Returns (leases or Unchecked, sandbox), sandbox being None when not asked, True when stuck, False when
    fine, or Unchecked."""
    began = time.monotonic()
    argv = {"leases": ["simlock", "list", "--leases"], "devices": ["simlock", "list", "--devices"]}
    if sandbox_bound is not None:
        argv["sandbox"] = SANDBOX_CHECK
    runs = {name: start(a) for name, a in argv.items()}
    try:
        done = {name: finish(run, began + (sandbox_bound if name == "sandbox" else lease_bound))
                for name, run in runs.items()}
    finally:
        for run in runs.values():
            if isinstance(run, subprocess.Popen) and run.returncode is None:
                try:
                    os.killpg(run.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                run.wait()
    return read_leases(done, lease_bound), read_sandbox(done.get("sandbox", "unasked"), sandbox_bound)


def read_leases(done, bound):
    """{UDID: (lease id, requester)} for every live lease, or Unchecked."""
    out = {}
    for what in ("leases", "devices"):
        result = done[what]
        if isinstance(result, OSError):
            return Unchecked(f"simlock did not start ({result})")
        if result is None:
            return Unchecked(f"simlock list took longer than {bound:g} s")
        if result[0]:
            return Unchecked(f"simlock list --{what} exited {result[0]}")
        out[what] = result[1]
    try:
        udids = {d["id"]: d["driverDeviceId"].upper() for d in json.loads(out["devices"]) if d.get("driverDeviceId")}
        now = time.time() * 1000
        return {udids[l["deviceId"]]: (l["id"], l.get("requesterId") or "")
                for l in json.loads(out["leases"])
                if l["deviceId"] in udids and l.get("ttlDeadline", now + 1) > now}
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        return Unchecked(f"simlock list printed what this hook cannot read ({error!r})")


def read_sandbox(result, bound):
    if result == "unasked":
        return None
    if isinstance(result, OSError):
        return Unchecked(f"hostgate did not start ({result})")
    if result is None:
        return Unchecked(f"hostgate check took longer than {bound:g} s")
    if result[0] in (0, 1):
        return result[0] == 1
    return Unchecked(f"hostgate check exited {result[0]}")


def callers(session):
    ids = {os.environ.get("CLAUDE_CODE_SESSION_ID"), session}
    return {f"claude-code:{i}" for i in ids if i}


def mine(requester, me):
    """True when the lease is the caller's, or when its requester is not an <agent>:<id> that says whose it is."""
    return not me or not AGENT_ID.fullmatch(requester) or requester in me


def refusal(tool, target, own, me, other):
    setting = tool == "session_set_defaults"
    then = "" if setting else f", then {tool} again"
    lines = [f"Refused: {tool} {'sets as the default only' if setting else 'runs only on'} a simulator your Simlock lease holds (ADR-0024),"]
    if target is None:
        lines.append("and this session has none: set it with session_set_defaults {simulatorId}.")
    elif other:
        lines.append(f"and {target} is leased by {other}, another agent (you are {' or '.join(sorted(me))}).")
    else:
        lines.append(f"and no live Simlock lease holds {target}.")
    if own:
        udid, lease = own
        lines += [
            f"You hold Simlock lease {lease} on {udid}. Call session_set_defaults {{simulatorId: \"{udid}\"}} alone{then}.",
        ]
    else:
        lines += [
            "1. Lease one. It waits up to 9 min for a free simulator, so give the shell 600 s, and prints the UDID and the lease id:",
            f"   {LEASE}",
            f"2. Call session_set_defaults {{simulatorId: \"<UDID>\"}} alone{then}.",
            "   The lease lasts 60 min: renew it with simlock lease renew <lease-id>, and give it back with simlock release <lease-id>.",
        ]
    lines += [
        "Or take the shell path, which leases, builds in a host build slot, installs and launches, and prints the UDID",
        "to set with session_set_defaults {simulatorId} for screenshot, snapshot_ui and touch (prefer touch with down and up; tap can miss):",
        f"   {VERIFY} build && {VERIFY} launch session",
    ]
    return "\n".join(lines)


def log_build(tool, session, udid, lease):
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    path = state_dir() / f"{REPO}.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as log:
        log.write(f"{stamp}\t{session}\t{tool}\t{udid}\t{lease}\n")


def allowed(warnings):
    text = "\n".join(warnings)
    return 0, text, {"systemMessage": text} if text else None


def interrupted(signum, _frame):
    raise Interrupted(signum)


def gate(tool, tool_input, session):
    """(exit status, stderr text, stdout JSON or None) for a PreToolUse call."""
    if tool in REFUSED:
        return 3, f"Refused: {tool} is off in this repo. {REFUSED[tool]}", None
    if tool == "session_set_defaults":
        named = [k for k in UNTRACKED if k in tool_input]
        if named:
            return 3, (
                f"Refused: session_set_defaults with {', '.join(named)} is off in this repo. A simulator name or a defaults profile"
                " can resolve to a simulator no Simlock lease holds (ADR-0024), and persist rewrites the tracked .xcodebuildmcp/config.yaml."
                " Call session_set_defaults {simulatorId: <your leased UDID>} alone."
            ), None
        if not tool_input.get("simulatorId"):
            return 0, "", None
        target = str(tool_input["simulatorId"]).upper()
    elif tool in ON_LEASE:
        named = [k for k in ("simulatorId", "simulatorName") if k in tool_input]
        if named:
            return 3, (
                f"Refused: {tool} takes no {' or '.join(named)} on this server. It runs on the session default, so the simulator"
                f" named here is not the one it would use. Call session_set_defaults {{simulatorId: <your leased UDID>}} alone,"
                f" then {tool} without {' or '.join(named)}."
            ), None
        target = recorded_udid(session)
        stray = stray_destination(tool_input.get("extraArgs"), target)
        if stray is not None:
            return 3, (
                f"Refused: {tool} would also run on -destination {stray} from extraArgs, and only the session default"
                f" ({target or 'none recorded'}) is checked against your Simlock lease (ADR-0024)."
                f" Drop -destination from extraArgs, then {tool} again. It runs on the session default."
            ), None
    else:
        return 0, "", None
    held_by, stuck = lookups(float(os.environ.get("SIM_HOOK_TIMEOUT", "8")),
                             float(os.environ.get("SIM_HOOK_SANDBOX_TIMEOUT", "12")) if tool in BUILDS else None)
    if stuck is True:
        return 3, SANDBOX_STUCK.format(tool=tool, verify=VERIFY), None
    warnings = []
    if isinstance(stuck, Unchecked):
        warnings.append(f"sim-mcp-hook: could not check host sandbox reporting before {tool}, because {stuck}."
                        " If the build hangs, run hostgate check.")
    if isinstance(held_by, Unchecked):
        warnings.append(f"sim-mcp-hook: allowed {tool} on {target or 'the session default'} unchecked, because {held_by}."
                        " Lease your simulator with simlock lease all the same.")
        if tool in BUILDS:
            log_build(tool, session, target or "-", "unchecked")
        return allowed(warnings)
    me = callers(session)
    lease, requester = held_by.get(target, (None, ""))
    if lease and mine(requester, me):
        if tool in BUILDS:
            log_build(tool, session, target, lease)
        return allowed(warnings)
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
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        status, text, out = gate(tool, tool_input, session)
    except Interrupted as signum:
        return 128 + signum.args[0]
    if text:
        print(text, file=sys.stderr)
    if out:
        print(json.dumps(out))
    return status


if __name__ == "__main__":
    sys.exit(main())
