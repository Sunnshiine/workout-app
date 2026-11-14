"""The lookups scripts/sim-mcp-hook.py makes: Simlock's live leases and devices, and hostgate's sandbox check,
each in its own process group so one cut short at its bound is ended with everything it started."""
import json
import os
import signal
import subprocess
import time

SANDBOX_CHECK = ["hostgate", "check", "--only", "sandbox-report"]


class Unchecked(Exception):
    """Simlock or hostgate could not answer."""


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
        end(runs.values())
    return read_leases(done, lease_bound), read_sandbox(done.get("sandbox", "unasked"), sandbox_bound)


def sandbox_lookup(deadline, bound):
    """The host sandbox check alone, ending at deadline, the hook's start plus bound, so a refusal that runs it
    after the lease lookups still answers within the hook's own bound."""
    run = start(SANDBOX_CHECK)
    try:
        return read_sandbox(finish(run, deadline), bound)
    finally:
        end([run])


def end(runs):
    """Ends each run still going with everything it started; its group is ours until run.wait() reaps it."""
    for run in runs:
        if isinstance(run, subprocess.Popen) and run.returncode is None:
            try:
                os.killpg(run.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            run.wait()


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
