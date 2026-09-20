#!/usr/bin/env python3
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
REPO = SKILL.parent.parent.parent
FIXTURES = Path(__file__).resolve().parent / "fixtures"
FRAME = re.compile(r"^@(-?\d+),(-?\d+) (\d+)x(\d+)$")

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


def tree_py(*args, stdin=""):
    done = subprocess.run(
        [sys.executable, str(SKILL / "tree.py")] + list(args),
        input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr


def verify_sh(*args, run):
    env = dict(os.environ, VERIFY_RUN=run)
    env.pop("SIM", None)
    done = subprocess.run(
        [str(SKILL / "verify.sh")] + list(args), cwd=str(REPO), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr


def write_png(path, width, height, colour):
    """A solid-colour PNG, so the sheet fixtures need no committed image."""
    scanlines = b"".join(b"\x00" + bytes(colour) * width for _ in range(height))

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


class Flat(unittest.TestCase):
    def test_flat_prints_only_what_is_on_screen(self):
        code, out, err = tree_py("flat", stdin=MINI)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (
            "AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n"
            "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n"
            "AXGroup\tactive-set-card\t\t\t@-83,476 4770x308\n"
            "AXStaticText\t\tRest 1:58 remaining\t\t@100,816 202x51\n"
        ), "the picker tail and the row below the fold are out; the wide card stays")
        self.assertIn("2 off-screen elements hidden", err, "the count of what was dropped")

    def test_the_screen_is_the_root_frame_even_when_the_root_prints_no_line(self):
        unlabeled = json.loads(MINI)
        del unlabeled[0]["AXLabel"]
        code, out, err = tree_py("flat", stdin=json.dumps(unlabeled))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (
            "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n"
            "AXGroup\tactive-set-card\t\t\t@-83,476 4770x308\n"
            "AXStaticText\t\tRest 1:58 remaining\t\t@100,816 202x51\n"
        ), "measured against the 402x874 root, not against whichever element happens to print first")

    def test_flat_all_keeps_the_off_screen_lines(self):
        code, out, err = tree_py("flat", "--all", stdin=MINI)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[:5], [
            "AXApplication\t\tWorkoutTracker\t\t@0,0 402x874",
            "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66",
            "AXButton\treps-100\tReps 100\t\t@4660,629 27x24",
            "AXGroup\tactive-set-card\t\t\t@-83,476 4770x308",
            "AXButton\tstage-queue-row-exercise-7\tFarmer Carry\t\t@23,900 312x52",
        ], "document order, the picker tail and the row below the fold included")
        self.assertEqual(err, "", "--all hides nothing, so it says nothing")

    def test_every_line_has_five_columns(self):
        out = tree_py("flat", "--all", stdin=MINI)[1]
        self.assertEqual(len(out.splitlines()), 6, "the element with neither id nor label is never printed")
        for line in out.splitlines():
            self.assertEqual(len(line.split("\t")), 5, line)
        self.assertIn("Rest 1:58 remaining", out, "a tab and a newline in a label become spaces")

    def test_the_session_tree_keeps_the_cards_that_run_off_both_edges(self):
        out = tree_py("flat", stdin=as_axe_json("01-before.all.txt"))[1]
        self.assertEqual(out, (FIXTURES / "01-before.tree.txt").read_text(), "the trimmed session tree")
        for line in ["AXGroup\tactive-set-card\t\t\t@-83,476 4770x308",
                     "AXGroup\t\tReps\t\t@-83,612 4770x83",
                     "AXGroup\t\tRPE\t\t@207,612 474x83"]:
            self.assertIn(line, out.splitlines(), "a card wider than the screen is still on it")

    def test_the_captured_trees_keep_what_intersects_the_screen(self):
        for fixture, kept, total in [("01-before.all.txt", 42, 139),
                                     ("02-after-log.all.txt", 47, 142),
                                     ("03-queue.all.txt", 59, 154)]:
            payload = as_axe_json(fixture)
            self.assertEqual(len(tree_py("flat", "--all", stdin=payload)[1].splitlines()), total, fixture)
            self.assertEqual(len(tree_py("flat", stdin=payload)[1].splitlines()), kept, fixture)


class Find(unittest.TestCase):
    def test_find_reaches_off_screen_elements_and_says_so(self):
        code, out, err = tree_py("find", "stage-queue-row-exercise-7", stdin=MINI)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "AXButton\tstage-queue-row-exercise-7\tFarmer Carry\t\t@23,900 312x52\n")
        self.assertIn("off-screen", err, "swipe it into view before tapping")

        code, out, err = tree_py("find", "weight-pill", stdin=MINI)
        self.assertEqual(code, 0)
        self.assertEqual(out, "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n")
        self.assertEqual(err, "", "an on-screen hit needs no warning")

        code, out, err = tree_py("find", "nope", stdin=MINI)
        self.assertEqual(code, 1, "absent is exit 1")
        self.assertEqual(out, "")

    def test_center_and_frame_still_answer(self):
        self.assertEqual(tree_py("center", "reps-100", stdin=MINI)[1], "4674 641\n", "hold still reaches off-screen ids")
        self.assertEqual(tree_py("frame", stdin=MINI)[1], "402 874\n", "swipe reads the screen size")
        self.assertEqual(tree_py("pid", stdin=MINI)[1], "4121\n", "doctor reads the frontmost pid")


class Diff(unittest.TestCase):
    def test_diff_of_the_log_a_set_shots_is_the_semantic_hunks(self):
        code, out, err = tree_py(
            "diff", str(FIXTURES / "01-before.tree.txt"), str(FIXTURES / "02-after-log.tree.txt"))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())
        for line in ["+ AXStaticText\t\tSync status: 1 unsynced\t\t@16,36 370x34",
                     "- AXStaticText\t\tSet 1 of 3\t\t@32,492 338x23",
                     "+ AXStaticText\t\tSet 2 of 3\t\t@32,480 338x23"]:
            self.assertIn(line, out.splitlines(), "the lines log-a-set.md tells the agent to quote")
        self.assertNotIn("stage-exercise-name", out, "it moved from y=133 to y=141 and did not change")
        self.assertEqual(out.splitlines()[-1], "23 changed, 33 unchanged")

    def test_a_pure_layout_shift_is_no_change(self):
        lines = []
        for line in (FIXTURES / "01-before.tree.txt").read_text().splitlines():
            head, frame = line.rsplit("\t", 1)
            x, y, width, height = FRAME.match(frame).groups()
            lines.append("%s\t@%s,%d %sx%s" % (head, x, int(y) + 8, width, height))
        with tempfile.TemporaryDirectory() as tmp:
            shifted = Path(tmp) / "shifted.tree.txt"
            shifted.write_text("\n".join(lines) + "\n")
            code, out, err = tree_py("diff", str(FIXTURES / "01-before.tree.txt"), str(shifted))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "no tree changes from 01-before to shifted, frames ignored\n")

    def test_a_missing_file_exits_66_and_names_it(self):
        code, out, err = tree_py("diff", str(FIXTURES / "01-before.tree.txt"), "/nope/gone.tree.txt")
        self.assertEqual(code, 66)
        self.assertIn("/nope/gone.tree.txt", err)
        self.assertEqual(out, "")


class VerifyDiff(unittest.TestCase):
    def setUp(self):
        self.run = "selftest-%d" % os.getpid()
        self.dir = REPO / ".build" / "verify" / "evidence" / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        for offset, name in enumerate(["01-before", "02-after-log"]):
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), self.dir / ("%s.tree.txt" % name))
            os.utime(self.dir / ("%s.tree.txt" % name), (offset, offset))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_verify_diff_maps_shot_names_onto_the_run(self):
        code, out, err = verify_sh("diff", "01-before", "02-after-log", run=self.run)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())

    def test_verify_diff_lists_the_shots_when_a_name_is_wrong(self):
        code, out, err = verify_sh("diff", "01-before", "03-typo", run=self.run)
        self.assertEqual(code, 1)
        self.assertIn("shots: 01-before 02-after-log", err, "capture order, so the agent can pick again")

    def test_a_png_whose_tree_never_landed_is_not_a_shot(self):
        (self.dir / "03-half.png").write_bytes(b"png")
        code, out, err = verify_sh("diff", "01-before", "03-half", run=self.run)
        self.assertEqual(code, 1)
        self.assertIn("shots: 01-before 02-after-log", err, "a shot exists when its tree exists")

    def test_a_run_name_that_is_not_a_plain_name_is_refused(self):
        for run in ["../escape", "two words", "-x"]:
            code, out, err = verify_sh("diff", "01-before", "02-after-log", run=run)
            self.assertEqual(code, 2, "%r must be refused before it becomes a path: %s" % (run, err))

    def test_shot_refuses_a_name_that_could_collide(self):
        for name in ["_sheet", "a.burst", "-x"]:
            code, out, err = verify_sh("shot", name, run=self.run)
            self.assertEqual(code, 2, "%s must be refused before any simulator is touched: %s" % (name, err))


@unittest.skipUnless(sys.platform == "darwin", "the tiler is a Swift script and runs on macOS only")
class VerifySheet(unittest.TestCase):
    """The agent's entry point, on a run whose capture order is not its name order."""

    def setUp(self):
        self.run = "sheettest-%d" % os.getpid()
        self.dir = REPO / ".build" / "verify" / "evidence" / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        for captured, name in enumerate(["02-b", "01-a", "03-c"]):
            write_png(self.dir / ("%s.png" % name), 120, 260, (32, 96, 160))
            tree = self.dir / ("%s.tree.txt" % name)
            tree.write_text("AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n")
            os.utime(tree, (captured + 1, captured + 1))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_the_sheet_numbers_every_shot_of_the_run_in_capture_order(self):
        code, out, err = verify_sh("sheet", run=self.run)
        self.assertEqual(code, 0, err)
        self.assertEqual(len(out.splitlines()), 1, "three shots are one page")
        fields = out.rstrip("\n").split("\t")
        self.assertEqual(len(fields), 5, out)
        self.assertEqual(fields[0], str(self.dir / "_sheet.png"), "one sheet per run, beside the shots")
        self.assertEqual(fields[2], "3 images")
        self.assertEqual(fields[4], "1. 02-b  2. 01-a  3. 03-c", "capture order, not name order")

    def test_a_second_sheet_of_the_same_shots_is_the_same_bytes(self):
        self.assertEqual(verify_sh("sheet", run=self.run)[0], 0)
        first = (self.dir / "_sheet.png").read_bytes()
        self.assertEqual(verify_sh("sheet", run=self.run)[0], 0)
        self.assertEqual((self.dir / "_sheet.png").read_bytes(), first, "rerunning converges")

    def test_a_run_with_no_shots_says_how_to_take_one(self):
        empty = self.dir.with_name("%s-empty" % self.run)
        empty.mkdir(parents=True, exist_ok=True)
        try:
            code, out, err = verify_sh("sheet", run=empty.name)
        finally:
            shutil.rmtree(empty, ignore_errors=True)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("shot NAME", err, "the way out of an empty run")


if __name__ == "__main__":
    unittest.main()
