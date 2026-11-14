import contextlib
import hashlib
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib
from pathlib import Path
from unittest import mock

SKILL = Path(__file__).resolve().parent.parent
REPO = SKILL.parent.parent.parent
FIXTURES = Path(__file__).resolve().parent / "fixtures"
FRAME = re.compile(r"^@(-?\d+),(-?\d+) (\d+)x(\d+)$")
sys.path.insert(0, str(SKILL))
import take  # noqa: E402
import tree  # noqa: E402


def link_checkout(root):
    """Links every file of scripts/ and of this skill into root, so a test never lists what a script sources."""
    skill = root / ".agents" / "skills" / "verify"
    for source, dest in [(REPO / "scripts", root / "scripts"), (SKILL, skill)]:
        dest.mkdir(parents=True, exist_ok=True)
        for path in source.iterdir():
            if path.is_file():
                (dest / path.name).symlink_to(path)
    return skill


MINI_TREE = [
    {
        "role": "AXApplication", "AXLabel": "WorkoutTracker", "pid": 4121,
        "frame": {"x": 0, "y": 0, "width": 402, "height": 874},
        "children": [
            {"role": "AXButton", "AXUniqueId": "weight-pill", "AXLabel": "Weight, 237.5",
             "frame": {"x": 98, "y": 531, "width": 206, "height": 66}},
            {"role": "AXButton", "AXUniqueId": "reps-100", "AXLabel": "Reps 100",
             "frame": {"x": 4660, "y": 629, "width": 27, "height": 24}},
            {"role": "AXGroup", "AXUniqueId": "active-set-card",
             "frame": {"x": -83, "y": 476, "width": 4770, "height": 308}},
            {"role": "AXButton", "AXUniqueId": "stage-queue-row-exercise-7", "AXLabel": "Farmer Carry",
             "frame": {"x": 23, "y": 900, "width": 312, "height": 52}},
            {"role": "AXStaticText", "AXLabel": "Rest\t1:58\nremaining", "AXValue": None,
             "frame": {"x": 100, "y": 816, "width": 202, "height": 51}},
            {"role": "AXGroup", "frame": {"x": 0, "y": 0, "width": 402, "height": 874}},
        ],
    }
]
MINI = json.dumps(MINI_TREE)
NAMELESS_FIELD = json.dumps([dict(MINI_TREE[0], children=MINI_TREE[0]["children"] + [
    {"role": "AXTextField", "AXValue": "Google Sheet URL", "frame": {"x": 32, "y": 459, "width": 338, "height": 34}}])])


def tree_py(*args, stdin=""):
    done = subprocess.run(
        [sys.executable, str(SKILL / "tree.py")] + list(args),
        input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr


def verify_sh(*args, run, sim=None, path=None, evidence=None, **extra):
    env = dict(os.environ, **extra)
    for name in ["VERIFY_RUN", "SIM"]:
        env.pop(name, None)
    if run:
        env["VERIFY_RUN"] = run
    if sim:
        env["SIM"] = sim
    if path:
        env["PATH"] = path
    if evidence:
        env["VERIFY_EVIDENCE"] = str(evidence)
    done = subprocess.run(
        [str(SKILL / "verify.sh")] + list(args), cwd=str(REPO), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr


def repo_git(*args):
    done = subprocess.run(["git", "-C", str(REPO)] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          universal_newlines=True)
    return done.returncode, done.stdout.strip()


def default_evidence():
    _, common = repo_git("rev-parse", "--path-format=absolute", "--git-common-dir")
    code, branch = repo_git("symbolic-ref", "--short", "-q", "HEAD")
    lane = re.sub(r"[^A-Za-z0-9._-]", "-", branch) if code == 0 else "detached-" + REPO.name
    return Path(common).parent / ".claude" / "work" / "evidence" / lane


def evidence_files(root):
    if not root.is_dir():
        return []
    return sorted((str(path.relative_to(root)), path.stat().st_size) for path in root.rglob("*") if path.is_file())


DEFAULT_EVIDENCE = default_evidence()
EVIDENCE_BEFORE = []


def without_simlock(path):
    """PATH minus every directory that holds a simlock, so no test can lease a real simulator."""
    return os.pathsep.join(d for d in path.split(os.pathsep) if not os.access(os.path.join(d, "simlock"), os.X_OK))


def fake_hostgate_first(path, scratch):
    """PATH with scripts/tests/fake-hostgate first, so no test takes or waits for a real host slot."""
    bin_dir = os.path.join(scratch, "hostgate-bin")
    os.makedirs(bin_dir, exist_ok=True)
    shutil.copy(SKILL.parents[2] / "scripts/tests/fake-hostgate", os.path.join(bin_dir, "hostgate"))
    return bin_dir + os.pathsep + path


FAKE_SIMLOCK = r'''#!/usr/bin/env python3
import fcntl, json, os, sys, time
STATE = {state!r}
args = sys.argv[1:]
with open(STATE + ".calls", "a") as log:
    log.write(" ".join(["simlock"] + args) + "\n")
if args[:1] == ["simctl"]:
    os.execvp("xcrun", ["xcrun"] + args)


def fail(code, error):
    print(json.dumps({{"error": {{"code": error, "message": error}}}}), file=sys.stderr)
    sys.exit(code)


def flag(name):
    return args[args.index(name) + 1] if name in args else None


now_ms = int(time.time() * 1000)
with open(STATE, "r+") as file:
    fcntl.flock(file, fcntl.LOCK_EX)
    state = json.load(file)
    principal = os.environ.get("SIMLOCK_AGENT_ID") or state["principal"]
    mine = [l for l in state["leases"] if l["requesterId"] == principal]
    if args == ["whoami"]:
        print("Principal: %s\nName:      %s\nRole:      agent\nVia:       socket" % (principal, principal))
    elif args == ["list", "--devices"]:
        udids = state["free"] + [l["udid"] for l in state["leases"]]
        print(json.dumps([{{"id": "dev_" + u, "driverDeviceId": u, "address": u, "state": "ready"}} for u in udids]))
    elif args == ["list", "--leases"]:
        print(json.dumps([{{k: v for k, v in dict(l, deviceId="dev_" + l["udid"]).items() if k != "udid"}}
                          for l in state["leases"]]))
    elif args[:2] == ["lease", "renew"]:
        lease = next((l for l in state["leases"] if l["id"] == args[2]), None) or fail(14, "LEASE_NOT_FOUND")
        lease["ttlDeadline"] = now_ms + lease["ttlMs"]
    elif args[:1] == ["lease"]:
        if mine:
            fail(13, "REQUESTER_ALREADY_LEASED")
        if not state["free"]:
            fail(10, "TIMEOUT")
        if "--detach" not in args:
            fail(64, "the fake simlock leases only with --detach")
        udid = state["free"].pop(0)
        ttl = int(flag("--ttl").rstrip("m")) * 60000
        lease = {{"id": "lse_" + udid, "udid": udid, "requesterId": principal, "ttlMs": ttl,
                  "ttlDeadline": now_ms + ttl}}
        state["leases"].append(lease)
        print(json.dumps({{"lease": {{"id": lease["id"], "ttlDeadline": lease["ttlDeadline"]}},
                          "device": {{"id": "dev_" + udid, "driverDeviceId": udid, "address": udid}}, "environment": {{}}}}))
    elif args[:1] == ["release"] and len(args) == 2:
        lease = next((l for l in mine if l["id"] == args[1]), None) or fail(14, "LEASE_NOT_FOUND")
        state["leases"].remove(lease)
        state["free"].append(lease["udid"])
    else:
        fail(64, "the fake simlock does not answer this")
    file.seek(0)
    file.truncate()
    json.dump(state, file)
'''


class FakeSimlock:
    """A simlock on bin_dir that leases the free UDIDs, records each call, and runs `simlock simctl` as xcrun simctl.
    Its caller is PRINCIPAL, or SIMLOCK_AGENT_ID when set, as Simlock reads it."""

    PRINCIPAL = "claude-code:verify-tests"

    def __init__(self, bin_dir, free=()):
        self.state = Path(bin_dir) / "simlock-state.json"
        self.state.write_text(json.dumps({"principal": self.PRINCIPAL, "free": list(free), "leases": []}))
        script = Path(bin_dir) / "simlock"
        script.write_text(FAKE_SIMLOCK.format(state=str(self.state)))
        script.chmod(0o755)

    def edit(self, change):
        state = json.loads(self.state.read_text())
        change(state)
        self.state.write_text(json.dumps(state))

    def hold(self, udid, minutes_left=60, minutes=60, requester=PRINCIPAL):
        """Gives requester, by default the caller, a lease on udid with minutes_left of its TTL to run."""
        lease = {"id": "lse_" + udid, "udid": udid, "requesterId": requester, "ttlMs": minutes * 60000,
                 "ttlDeadline": int((time.time() + minutes_left * 60) * 1000)}
        self.edit(lambda state: state["leases"].append(lease))
        return lease["id"]

    def leases(self):
        return [(l["udid"], l["requesterId"]) for l in json.loads(self.state.read_text())["leases"]]

    def calls(self):
        log = Path(str(self.state) + ".calls")
        return log.read_text().splitlines() if log.exists() else []


def leased_path(bin_dir, sim):
    """A PATH whose fake simlock, in bin_dir, holds sim for the caller."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    FakeSimlock(bin_dir).hold(sim)
    return "%s%s%s" % (bin_dir, os.pathsep, os.environ["PATH"])


def setUpModule():
    locks = tempfile.mkdtemp(prefix="workout-host-locks-")
    unittest.addModuleCleanup(shutil.rmtree, locks, True)
    os.environ.update(WORKOUT_MEM_FLOOR="0", WORKOUT_DISK_FLOOR="0",
                      WORKOUT_HOST_LOCK_DIR=locks, HOSTGATE_STATE_DIR=os.path.join(locks, "hostgate"),
                      WORKOUT_DEV_USAGE_DIR=os.path.join(locks, "dev-usage"),
                      PATH=fake_hostgate_first(without_simlock(os.environ["PATH"]), locks))
    os.environ.pop("HOSTGATE_SLOT", None)
    EVIDENCE_BEFORE[:] = evidence_files(DEFAULT_EVIDENCE)
    os.environ["VERIFY_EVIDENCE"] = tempfile.mkdtemp()


def tearDownModule():
    shutil.rmtree(os.environ.pop("VERIFY_EVIDENCE"), ignore_errors=True)
    after = evidence_files(DEFAULT_EVIDENCE)
    if after != EVIDENCE_BEFORE:
        raise AssertionError("the tests wrote into this checkout's own evidence %s: %s"
                             % (DEFAULT_EVIDENCE, sorted(set(after) - set(EVIDENCE_BEFORE))))


def write_png(path, width, height, colour, box_frame=(0, 0, 0, 0), box_colour=None):
    plain = b"\x00" + bytes(colour) * width
    (x, y, w, h), inside = box_frame, box_colour or colour
    band = b"\x00" + bytes(colour) * x + bytes(inside) * w + bytes(colour) * (width - x - w)
    scanlines = b"".join(band if y <= row < y + h else plain for row in range(height))

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(scanlines))
        + chunk(b"IEND", b"")
    )


def as_axe_json(fixture):
    nodes = []
    for line in (FIXTURES / fixture).read_text().splitlines():
        role, ident, label, value, frame = line.split("\t")
        x, y, width, height = (int(n) for n in FRAME.match(frame).groups())
        nodes.append({
            "role": role, "AXUniqueId": ident or None, "AXLabel": label or None,
            "AXValue": value or None, "pid": 4121,
            "frame": {"x": x, "y": y, "width": width, "height": height},
        })
    nodes[0]["children"] = nodes[1:]
    return json.dumps([nodes[0]])


HOME_SCREEN = (FIXTURES / "home-screen.describe-ui.json").read_text()
SETTINGS = (FIXTURES / "settings.describe-ui.json").read_text()
APP = "53393"
GEAR_UP = (FIXTURES / "gear-point-controls-up.describe-ui.json").read_text()
GEAR_HIDDEN = (FIXTURES / "gear-point-controls-hidden.describe-ui.json").read_text()
COVERED = "; something is over it, or it left the screen after the tree was read\n"
GEAR_COVERED = ("covered: at 356,87 the screen has AXStaticText session-remaining-count @317,77 55x19, "
                "not AXButton session-controls-settings-button" + COVERED)
BEFORE_TREE = str(FIXTURES / "01-before.tree.txt")


def on_screen_of_402x874(*children):
    return json.dumps([{"role": "AXApplication", "pid": 1, "frame": {"x": 0, "y": 0, "width": 402, "height": 874},
                        "children": list(children)}])


HALF_ROW = {"role": "AXButton", "AXUniqueId": "half-row", "AXLabel": "Row",
            "frame": {"x": 23, "y": 850, "width": 312, "height": 52}}
WIDE_CARD = {"role": "AXGroup", "AXUniqueId": "active-set-card", "frame": {"x": -83, "y": 476, "width": 4770, "height": 308}}
