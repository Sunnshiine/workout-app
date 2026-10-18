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


def setUpModule():
    locks = tempfile.mkdtemp(prefix="workout-host-locks-")
    unittest.addModuleCleanup(shutil.rmtree, locks, True)
    os.environ.update(WORKOUT_LOAD_LIMIT="1000000", WORKOUT_MEM_FLOOR="0", WORKOUT_SIM_CAP="1000", WORKOUT_BUILD_SLOTS="100",
                      WORKOUT_HOST_LOCK_DIR=locks)
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
