#!/usr/bin/env python3
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
    os.environ.update(WORKOUT_LOAD_LIMIT="1000000", WORKOUT_SIM_CAP="1000", WORKOUT_BUILD_SLOTS="100",
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

    def test_an_element_that_only_touches_the_screen_edge_is_off_screen(self):
        edges = json.loads(MINI)
        edges[0]["children"] = [
            {"role": "AXButton", "AXUniqueId": "last-visible-row", "frame": {"x": 0, "y": 873, "width": 300, "height": 40}},
            {"role": "AXButton", "AXUniqueId": "first-row-below", "frame": {"x": 0, "y": 874, "width": 300, "height": 40}},
            {"role": "AXButton", "AXUniqueId": "first-column-right", "frame": {"x": 402, "y": 100, "width": 27, "height": 24}},
            {"role": "AXButton", "AXUniqueId": "ends-at-the-left-edge", "frame": {"x": -27, "y": 100, "width": 27, "height": 24}},
        ]
        code, out, err = tree_py("flat", stdin=json.dumps(edges))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (
            "AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n"
            "AXButton\tlast-visible-row\t\t\t@0,873 300x40\n"
        ), "a 402x874 screen shows points 0 to 873; a row starting at 874 has no visible point")

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
        self.assertEqual(len(out.splitlines()), 7, "the element with neither id nor label is printed too")
        for line in out.splitlines():
            self.assertEqual(len(line.split("\t")), 5, line)
        self.assertIn("Rest 1:58 remaining", out, "a tab and a newline in a label become spaces")

    def test_all_prints_an_element_with_neither_id_nor_label_by_its_role_value_and_frame(self):
        nameless = json.loads(MINI)
        nameless[0]["children"].append(
            {"role": "AXTextField", "AXValue": "Google Sheet URL", "frame": {"x": 32, "y": 459, "width": 338, "height": 34}})
        payload = json.dumps(nameless)
        code, out, err = tree_py("flat", "--all", stdin=payload)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[-2:], [
            "AXGroup\t\t\t\t@0,0 402x874",
            "AXTextField\t\t\tGoogle Sheet URL\t@32,459 338x34",
        ], "issue 666: a field with no name is still on the screen, so --all shows it")
        code, out, err = tree_py("flat", stdin=payload)
        self.assertNotIn("Google Sheet URL", out, "the plain tree stays the named elements a shot saves")
        self.assertEqual(err, (
            "2 off-screen elements hidden; `verify.sh tree --all` lists them\n"
            "2 elements with neither id nor label hidden; `verify.sh tree --all` lists them\n"
        ), "each kind of drop is counted, so a missing line is never read as a missing element")

    def test_all_on_the_captured_settings_screen_prints_every_node(self):
        payload = (FIXTURES / "settings.describe-ui.json").read_text()
        self.assertEqual(len(tree_py("flat", "--all", stdin=payload)[1].splitlines()), 93,
                         "34 named and 59 unnamed nodes, as axe describe-ui returned them")

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

    def test_find_says_when_the_element_is_disabled(self):
        tree = json.loads(MINI)
        tree[0]["children"].append({
            "role": "AXButton", "AXUniqueId": "settings-sign-out-button", "AXLabel": "Sign Out", "enabled": False,
            "frame": {"x": 16, "y": 657, "width": 370, "height": 52},
        })
        tree[0]["children"][0]["enabled"] = True
        code, out, err = tree_py("find", "settings-sign-out-button", stdin=json.dumps(tree))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "AXButton\tsettings-sign-out-button\tSign Out\t\t@16,657 370x52\n", "the line keeps its five columns")
        self.assertIn("disabled", err, "a tap on it does nothing")
        self.assertEqual(tree_py("find", "weight-pill", stdin=json.dumps(tree))[2], "", "an enabled hit needs no warning")

    def test_frame_of_prints_the_first_hits_frame_or_none_and_fails_only_on_a_broken_tree(self):
        self.assertEqual(tree_py("frame-of", "active-set-card", stdin=MINI), (0, "@-83,476 4770x308\n", ""))
        self.assertEqual(tree_py("frame-of", "stage-queue-row-exercise-7", stdin=MINI), (0, "@23,900 312x52\n", ""),
                         "off-screen is still a frame")
        self.assertEqual(tree_py("frame-of", "nope", stdin=MINI), (0, "none\n", ""))
        self.assertNotEqual(tree_py("frame-of", "active-set-card", stdin="")[0], 0)

    def test_center_and_frame_still_answer(self):
        self.assertEqual(tree_py("center", "reps-100", stdin=MINI)[1], "4674 641\n", "hold still reaches off-screen ids")
        self.assertEqual(tree_py("frame", stdin=MINI)[1], "402 874\n", "swipe reads the screen size")
        self.assertEqual(tree_py("pid", stdin=MINI)[1], "4121\n", "doctor reads the frontmost pid")


def with_disabled(**overrides):
    tree = json.loads(MINI)
    node = {"role": "AXButton", "AXUniqueId": "clear-write-log-button", "AXLabel": "Clear Write Log",
            "enabled": False, "frame": {"x": 32, "y": 773, "width": 338, "height": 35}}
    node.update(overrides)
    tree[0]["children"].append(node)
    return json.dumps(tree)


class Tappable(unittest.TestCase):
    def test_tappable_is_the_centre_of_an_enabled_on_screen_hit(self):
        code, out, err = tree_py("tappable", "weight-pill", stdin=MINI)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "201 564\nAXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n",
                         "the point verify.sh hands to axe, then the line landing checks the point read against")
        self.assertEqual(err, "", "a tap that can land says nothing")

    def test_tappable_refuses_a_row_below_the_fold(self):
        code, out, err = tree_py("tappable", "stage-queue-row-exercise-7", stdin=MINI)
        self.assertEqual(code, 1, "tapping its frame centre would hit nothing")
        self.assertEqual(out, "", "no point, so verify.sh has nothing to tap")
        self.assertEqual(err, "off-screen: swipe it into view before tapping\n")

    def test_tappable_refuses_a_disabled_element(self):
        code, out, err = tree_py("tappable", "clear-write-log-button", stdin=with_disabled())
        self.assertEqual(code, 1, "the tap axe reported as a success was a no-op")
        self.assertEqual(out, "")
        self.assertEqual(err, "disabled: a tap on it does nothing\n")

    def test_tappable_names_an_id_that_is_not_on_the_screen_at_all(self):
        code, out, err = tree_py("tappable", "nope", stdin=MINI)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("nope", err, "which id failed, because the recipe may have the wrong one")

    def test_tappable_and_find_speak_the_same_two_notes(self):
        both = with_disabled(frame={"x": 32, "y": 1132, "width": 338, "height": 38})
        found = tree_py("find", "clear-write-log-button", stdin=both)
        refused = tree_py("tappable", "clear-write-log-button", stdin=both)
        self.assertEqual(found[0], 0, "find reports and exits 0")
        self.assertEqual(refused[0], 1, "tappable reports and refuses")
        self.assertEqual(refused[2], found[2], "one vocabulary for both, so neither can drift")
        self.assertEqual(refused[2].splitlines(), [
            "off-screen: swipe it into view before tapping",
            "disabled: a tap on it does nothing",
        ], "an element can be both, and each note names a different fix")

    def test_tappable_takes_the_hit_that_can_receive_the_tap(self):
        twins = json.loads(MINI)
        twins[0]["children"] = [
            {"role": "AXButton", "AXUniqueId": "Save", "frame": {"x": 23, "y": 900, "width": 312, "height": 52}},
            {"role": "AXButton", "AXUniqueId": "Save", "frame": {"x": 100, "y": 200, "width": 200, "height": 40}},
        ]
        code, out, err = tree_py("tappable", "Save", stdin=json.dumps(twins))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "200 220\nAXButton\tSave\t\t\t@100,200 200x40\n", "the scrolled-out twin is not a reason to refuse a tap that lands")


SESSION_RAILS = (FIXTURES / "session-rails.describe-ui.json").read_text()
KEYBOARD_DONE = (FIXTURES / "keyboard-done.describe-ui.json").read_text()
HOME_SCREEN = (FIXTURES / "home-screen.describe-ui.json").read_text()
SETTINGS = (FIXTURES / "settings.describe-ui.json").read_text()
SIGN_OUT_ALERT = (FIXTURES / "settings-sign-out-alert.describe-ui.json").read_text()
RPE_CLIPPED = "clipped: outside AXGroup RPE @207,612 163x83; bring it inside that frame before tapping\n"
REPS_CLIPPED = "clipped: outside AXGroup Reps @32,612 163x83; bring it inside that frame before tapping\n"


class Clipped(unittest.TestCase):
    def test_find_says_a_chip_the_rail_does_not_draw_is_clipped_and_names_the_rail(self):
        code, out, err = tree_py("find", "rpe-7", stdin=SESSION_RAILS)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "AXButton\trpe-7\tRPE 7\t\t@380,629 9x24\n", "inside the 402-point screen")
        self.assertEqual(err, RPE_CLIPPED, "the RPE track ends at x 370 and the chip starts at 380")

    def test_tappable_refuses_a_chip_the_rail_does_not_draw(self):
        code, out, err = tree_py("tappable", "rpe-7", stdin=SESSION_RAILS)
        self.assertEqual(code, 1, "axe tapped 384,641, reported success, and the log button stayed at @6")
        self.assertEqual(out, "")
        self.assertEqual(err, RPE_CLIPPED)

    def test_tappable_refuses_a_chip_whose_centre_is_drawn_over_by_another_control(self):
        code, out, err = tree_py("tappable", "reps-9", stdin=SESSION_RAILS)
        self.assertEqual(code, 1, "the point 305,641 hit-tests to rpe-6, so the tap would pick an RPE")
        self.assertEqual(err, REPS_CLIPPED)

    def test_the_nearest_ancestor_that_misses_the_chip_is_the_one_named(self):
        code, out, err = tree_py("tappable", "reps-11", stdin=SESSION_RAILS)
        self.assertEqual(code, 1)
        self.assertEqual(err, REPS_CLIPPED, "reps-11 at x 392 misses the card too, but the rail is what clips it")

    def test_a_chip_the_rail_draws_still_taps(self):
        self.assertEqual(tree_py("tappable", "rpe-6.5", stdin=SESSION_RAILS)[1:],
                         ("336 641\nAXButton\trpe-6.5\tRPE 6.5\t\t@325,629 23x24\n", ""))
        self.assertEqual(tree_py("tappable", "rpe-6", stdin=SESSION_RAILS)[1:],
                         ("289 641\nAXButton\trpe-6\tRPE 6\t\t@268,622 42x38\n", ""))
        self.assertEqual(tree_py("find", "rpe-5", stdin=SESSION_RAILS)[2], "", "the first chip inside the track")

    def test_a_chip_across_the_track_edge_is_clipped_when_its_centre_is_outside(self):
        def rpe_7_at(x):
            tree = json.loads(SESSION_RAILS)
            stack = [tree[0]]
            while stack:
                node = stack.pop()
                if node.get("AXUniqueId") == "rpe-7":
                    node["frame"]["x"] = x
                stack.extend(node.get("children", []))
            return json.dumps(tree)

        self.assertEqual(tree_py("tappable", "rpe-7", stdin=rpe_7_at(367))[::2], (1, RPE_CLIPPED),
                         "x 367 to 376 overlaps the track, which ends at 370, but the tap at 372 is past it")
        self.assertEqual(tree_py("tappable", "rpe-7", stdin=rpe_7_at(364))[:2], (0, "368 641\nAXButton\trpe-7\tRPE 7\t\t@364,629 9x24\n"),
                         "x 364 to 373 pokes past the track, but the tap at 368 lands inside it")

    def test_an_off_screen_chip_outside_its_rail_gets_both_notes(self):
        code, out, err = tree_py("find", "reps-100", stdin=SESSION_RAILS)
        self.assertEqual(code, 0, err)
        self.assertEqual(err.splitlines(), [
            "off-screen: swipe it into view before tapping",
            REPS_CLIPPED.rstrip("\n"),
        ], "a swipe of the screen never brings a rail chip in, so the second note names the fix")

    def test_a_row_below_the_fold_of_a_full_screen_scroll_area_is_only_off_screen(self):
        scrolled = json.loads(MINI)
        scrolled[0]["children"] = [{
            "role": "AXScrollArea", "frame": {"x": 0, "y": 0, "width": 402, "height": 874},
            "children": [{"role": "AXButton", "AXUniqueId": "developer-tools-row", "AXLabel": "Write Log",
                          "frame": {"x": 16, "y": 1180, "width": 370, "height": 52}}],
        }]
        code, out, err = tree_py("find", "developer-tools-row", stdin=json.dumps(scrolled))
        self.assertEqual(code, 0, err)
        self.assertEqual(err, "off-screen: swipe it into view before tapping\n",
                         "the scroll area is the screen, so naming it again would repeat the swipe")

    def test_a_track_two_levels_up_clips_a_chip_its_content_row_holds(self):
        nested = json.loads(MINI)
        nested[0]["children"] = [{
            "role": "AXGroup", "AXLabel": "RPE", "frame": {"x": 207, "y": 612, "width": 163, "height": 83},
            "children": [{
                "role": "AXGroup", "frame": {"x": 207, "y": 612, "width": 474, "height": 83},
                "children": [{"role": "AXButton", "AXUniqueId": "rpe-7", "AXLabel": "RPE 7",
                              "frame": {"x": 380, "y": 629, "width": 9, "height": 24}}],
            }],
        }]
        tree = json.dumps(nested)
        self.assertEqual(tree_py("find", "rpe-7", stdin=tree),
                         (0, "AXButton\trpe-7\tRPE 7\t\t@380,629 9x24\n", RPE_CLIPPED),
                         "the 474-point content row holds the chip, but the track above it ends at x 370")
        self.assertEqual(tree_py("tappable", "rpe-7", stdin=tree), (1, "", RPE_CLIPPED))

    def test_a_row_scrolled_up_under_the_nav_bar_is_clipped_on_the_y_axis_alone(self):
        scrolled = json.loads(MINI)
        scrolled[0]["children"] = [{
            "role": "AXScrollArea", "frame": {"x": 0, "y": 100, "width": 402, "height": 774},
            "children": [{"role": "AXButton", "AXUniqueId": "developer-tools-row", "AXLabel": "Write Log",
                          "frame": {"x": 16, "y": 60, "width": 370, "height": 52}}],
        }]
        tree = json.dumps(scrolled)
        above_the_top = "clipped: outside AXScrollArea @0,100 402x774; bring it inside that frame before tapping\n"
        self.assertEqual(tree_py("find", "developer-tools-row", stdin=tree),
                         (0, "AXButton\tdeveloper-tools-row\tWrite Log\t\t@16,60 370x52\n", above_the_top),
                         "x 201 is inside the scroll area; y 86 is above its top edge at 100")
        self.assertEqual(tree_py("tappable", "developer-tools-row", stdin=tree), (1, "", above_the_top))

    def test_a_zero_size_group_in_the_keyboard_toolbar_does_not_clip_done(self):
        done = "AXButton\tweight-keyboard-done\tDone\t\t@319,798 62x36\n"
        self.assertEqual(tree_py("find", "weight-keyboard-done", stdin=KEYBOARD_DONE), (0, done, ""),
                         "an AXGroup @16,792 0x0 sits between the toolbar and Done, and Done is drawn")
        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=KEYBOARD_DONE), (0, "350 816\n" + done, ""),
                         "a tap at 350,816 closed the keyboard on the live app")

    def test_only_a_group_with_a_zero_side_is_skipped(self):
        def group_sized(width, height):
            tree = json.loads(KEYBOARD_DONE)
            stack = [tree[0]]
            while stack:
                node = stack.pop()
                if node["frame"] == {"x": 16, "y": 792, "width": 0, "height": 0}:
                    node["frame"].update(width=width, height=height)
                stack.extend(node.get("children", []))
            return json.dumps(tree)

        done = "350 816\nAXButton\tweight-keyboard-done\tDone\t\t@319,798 62x36\n"
        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=group_sized(0, 48)), (0, done, ""))
        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=group_sized(370, 0)), (0, done, ""))
        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=group_sized(1, 48)), (
            1, "", "clipped: outside AXGroup @16,792 1x48; bring it inside that frame before tapping\n",
        ), "a group one point wide still holds points, and not the one Done is tapped at")

    def test_a_track_above_a_zero_size_group_still_clips_the_chip(self):
        wrapped = json.loads(MINI)
        wrapped[0]["children"] = [{
            "role": "AXGroup", "AXLabel": "RPE", "frame": {"x": 207, "y": 612, "width": 163, "height": 83},
            "children": [{
                "role": "AXGroup", "frame": {"x": 207, "y": 612, "width": 0, "height": 0},
                "children": [{"role": "AXButton", "AXUniqueId": "rpe-7", "AXLabel": "RPE 7",
                              "frame": {"x": 380, "y": 629, "width": 9, "height": 24}}],
            }],
        }]
        self.assertEqual(tree_py("tappable", "rpe-7", stdin=json.dumps(wrapped)), (1, "", RPE_CLIPPED),
                         "the zero-size group is skipped and the walk goes on to the track")

    def test_a_zero_size_button_around_the_home_screen_icons_does_not_clip_them(self):
        self.assertEqual(tree_py("tappable", "WorkoutTracker", stdin=HOME_SCREEN),
                         (0, "62 336\nAXButton\tWorkoutTracker\tWorkoutTracker\t\t@10,289 105x94\n", ""),
                         "live-activity.md reopens the app with tap --id WorkoutTracker; the icon sits in an AXButton @0,0 0x0")

    def test_on_the_captured_screen_exactly_the_chips_a_tap_misses_are_clipped(self):
        on_screen = [line.split("\t")[1] for line in tree_py("flat", stdin=SESSION_RAILS)[1].splitlines()]
        clipped = [ident for ident in on_screen if ident and "clipped" in tree_py("find", ident, stdin=SESSION_RAILS)[2]]
        self.assertEqual(clipped, ["reps-3", "reps-7", "reps-8", "reps-9", "reps-10", "reps-11", "rpe-7"],
                         "describe-ui --point at each centre on the live app returned something else for these seven")


class TappableByLabel(unittest.TestCase):
    def test_a_label_on_one_enabled_on_screen_element_is_its_centre(self):
        self.assertEqual(tree_py("tappable", "--label", "Weight, 237.5", stdin=MINI),
                         (0, "201 564\nAXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n", ""))

    def test_a_control_wins_over_the_text_that_shares_its_label(self):
        for label, point in [
            ("Developer Tools", "201 596\nAXButton\tsettings-developer-tools-row\tDeveloper Tools\t\t@16,570 370x52\n"),
            ("Standard, 2:00", "201 353\nAXSlider\tsettings-standard-rest-stepper\tStandard, 2:00\t120\t@32,337 338x32\n"),
        ]:
            with self.subTest(label=label):
                self.assertEqual(tree_py("tappable", "--label", label, stdin=SETTINGS), (0, point, ""))

    def test_a_label_only_a_text_carries_is_that_texts_centre(self):
        self.assertEqual(tree_py("tappable", "--label", "Standard", stdin=SETTINGS),
                         (0, "67 353\nAXStaticText\t\tStandard\t\t@32,343 70x20\n", ""))

    def test_spaces_around_the_label_are_trimmed(self):
        self.assertEqual(tree_py("tappable", "--label", "  Sign Out ", stdin=SETTINGS),
                         (0, "201 683\nAXButton\tsettings-sign-out-button\tSign Out\t\t@16,657 370x52\n", ""))

    def test_two_texts_with_one_label_and_no_control_are_listed(self):
        self.assertEqual(tree_py("tappable", "--label", "RPE", stdin=SESSION_RAILS), (1, "", "\n".join([
            "2 elements carry the label RPE; pick one by its id, or tap its centre with -x -y:",
            "AXGroup\t\tRPE\t\t@207,612 163x83\t-x 288 -y 654",
            "AXStaticText\t\tRPE\t\t@278,678 21x17\t-x 289 -y 687",
        ]) + "\n"), "the rail and its caption; neither wins, so neither is tapped")

    def test_a_label_below_the_fold_is_refused(self):
        self.assertEqual(tree_py("tappable", "--label", "Farmer Carry", stdin=MINI),
                         (1, "", "off-screen: swipe it into view before tapping\n"))

    def test_a_disabled_label_is_refused(self):
        self.assertEqual(tree_py("tappable", "--label", "Clear Write Log", stdin=with_disabled()),
                         (1, "", "disabled: a tap on it does nothing\n"))

    def test_a_chip_the_rail_does_not_draw_is_refused_by_its_label(self):
        self.assertEqual(tree_py("tappable", "--label", "RPE 7", stdin=SESSION_RAILS), (1, "", RPE_CLIPPED),
                         "RPE 7.5 is a different label, so the match is exact")

    def test_two_controls_with_one_label_are_listed_with_their_centres(self):
        code, out, err = tree_py("tappable", "--label", "Sign Out", stdin=SIGN_OUT_ALERT)
        self.assertEqual((code, out), (1, ""))
        self.assertEqual(err.splitlines(), [
            "2 elements carry the label Sign Out; pick one by its id, or tap its centre with -x -y:",
            "AXButton\tsettings-sign-out-button\tSign Out\t\t@16,657 370x52\t-x 201 -y 683",
            "AXButton\t\tSign Out\t\t@205,484 140x48\t-x 275 -y 508",
        ], "the Settings row behind the alert, then the alert's own button")

    def test_a_label_nothing_carries_is_named(self):
        self.assertEqual(tree_py("tappable", "--label", "Sign out", stdin=SETTINGS),
                         (1, "", "no element with label Sign out\n"), "the match is case-sensitive")

    def test_a_blank_label_matches_nothing(self):
        self.assertEqual(tree_py("tappable", "--label", " ", stdin=MINI), (1, "", "no element with label  \n"),
                         "active-set-card has an id and no label, and a blank query must not reach it")


GEAR = "AXButton\tsession-controls-settings-button\tSettings\t\t@334,65 44x44"
APP = "53393"
WEIGHT_PILL = "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66"
GEAR_UP = (FIXTURES / "gear-point-controls-up.describe-ui.json").read_text()
GEAR_HIDDEN = (FIXTURES / "gear-point-controls-hidden.describe-ui.json").read_text()
COVERED = "; something is over it, or it left the screen after the tree was read\n"
GEAR_COVERED = ("covered: at 356,87 the screen has AXStaticText session-remaining-count @317,77 55x19, "
                "not AXButton session-controls-settings-button" + COVERED)


class Landing(unittest.TestCase):
    def test_the_target_itself_at_its_centre_lands(self):
        self.assertEqual(tree_py("landing", GEAR, APP, stdin=GEAR_UP), (0, "", ""), "the live read with the controls up")
        self.assertEqual(tree_py("landing", GEAR.replace("@334,65", "@334,40"), APP, stdin=GEAR_UP), (0, "", ""),
                         "its own id lands even when its frame moved between the two reads")

    def test_a_child_inside_the_target_lands(self):
        child = [{"role": "AXStaticText", "AXLabel": "237.5", "pid": 53393,
                  "frame": {"x": 110, "y": 545, "width": 180, "height": 40}}]
        self.assertEqual(tree_py("landing", WEIGHT_PILL, APP, stdin=json.dumps(child)), (0, "", ""),
                         "the text drawn inside the pill wins the hit test, and the tap still lands on the pill")

    def test_the_alert_backdrop_over_the_sign_out_row_is_covered(self):
        backdrop = (FIXTURES / "sign-out-row-under-alert.describe-ui.json").read_text()
        row = "AXButton\tsettings-sign-out-button\tSign Out\t\t@16,657 370x52"
        self.assertEqual(tree_py("landing", row, "62389", stdin=backdrop), (1, "", (
            "covered: at 201,683 the screen has AXGroup @0,0 402x874, not AXButton settings-sign-out-button" + COVERED
        )), "the full tree still lists the row under the alert; the live point read returned the backdrop")

    def test_the_header_text_where_the_hidden_gear_was_is_covered(self):
        self.assertEqual(tree_py("landing", GEAR, APP, stdin=GEAR_HIDDEN), (1, "", GEAR_COVERED),
                         "the controls hid 2.5 s after the drag, between the tree read and the point read")

    def test_nothing_at_the_point_is_covered(self):
        for answer in ["", "[]"]:
            with self.subTest(answer=answer):
                self.assertEqual(tree_py("landing", WEIGHT_PILL, APP, stdin=answer), (
                    1, "", "covered: at 201,564 the screen has nothing, not AXButton weight-pill" + COVERED))

    def test_a_frame_within_a_point_of_the_printed_edges_lands(self):
        done = "AXButton\t\tDone\t\t@316,66 66x36"

        def hit_at(x):
            return json.dumps({"role": "AXStaticText", "AXLabel": "Done", "pid": 53393,
                               "frame": {"x": x, "y": 65.667, "width": 65.667, "height": 36.333}})

        self.assertEqual(tree_py("landing", done, APP, stdin=hit_at(316.333)), (0, "", ""),
                         "the button's own fractional frame, printed as @316,66 66x36")
        self.assertEqual(tree_py("landing", done, APP, stdin=hit_at(317)), (0, "", ""),
                         "a child whose right edge, 382.667, passes the printed 382 by less than a point")
        self.assertEqual(tree_py("landing", done, APP, stdin=hit_at(314.6)), (1, "", (
            "covered: at 349,84 the screen has AXStaticText Done @315,66 66x36, not AXButton Done" + COVERED
        )), "a frame more than a point past the left edge is something else")

    def test_a_point_read_from_another_process_over_the_app_is_covered(self):
        for hit in [{"role": "AXButton", "AXLabel": "Allow", "pid": 111}, {"role": "AXButton", "AXLabel": "Allow"}]:
            with self.subTest(pid=hit.get("pid")):
                hit["frame"] = {"x": 334, "y": 65, "width": 44, "height": 44}
                self.assertEqual(tree_py("landing", GEAR, APP, stdin=json.dumps(hit)), (1, "", (
                    "covered: at 356,87 the screen has AXButton Allow @334,65 44x44, "
                    "not AXButton session-controls-settings-button" + COVERED
                )), "a system prompt the size of the gear, or a hit with no process, is not the app's gear")



CROP_USAGE = "usage: tree.py crop SHOT.tree.txt PNG_WIDTH ID | crop SHOT.tree.txt PNG_WIDTH X Y W H\n"
BEFORE_TREE = str(FIXTURES / "01-before.tree.txt")


class CropRegion(unittest.TestCase):
    def test_an_id_is_its_frame_with_8_points_around_it(self):
        self.assertEqual(tree_py("crop", BEFORE_TREE, "1206", "weight-pill"), (0, "270 1569 666 246 90_523_222x82\n", ""),
                         "weight-pill @98,531 206x66, 3 pixels a point")

    def test_the_scale_is_the_png_width_over_the_screen_width(self):
        self.assertEqual(tree_py("crop", BEFORE_TREE, "804", "weight-pill"), (0, "180 1046 444 164 90_523_222x82\n", ""),
                         "a 2x device, same points")
        self.assertEqual(tree_py("crop", BEFORE_TREE, "1000", "1", "1", "1", "1"), (0, "2 2 3 3 1_1_1x1\n", ""),
                         "2.49 pixels a point: 2.49 to 4.98 rounds outward to 2 to 5")

    def test_the_region_is_clipped_to_the_screen(self):
        self.assertEqual(tree_py("crop", BEFORE_TREE, "1206", "session-header-hud"), (0, "0 162 1206 177 0_54_402x59\n", ""),
                         "the header spans the width, so its padding falls off both sides")
        self.assertEqual(tree_py("crop", str(FIXTURES / "02-after-log.tree.txt"), "1206", "rest-pill"),
                         (0, "276 2424 654 198 92_808_218x66\n", ""), "the pill's padding falls off the bottom")
        self.assertEqual(tree_py("crop", BEFORE_TREE, "1206", "380", "860", "100", "100"),
                         (0, "1140 2580 66 42 380_860_22x14\n", ""), "points past the corner")

    def test_an_absent_id_lists_the_ids_the_shot_has(self):
        shot = Path(tempfile.mkdtemp())
        try:
            (shot / "03-queue.tree.txt").write_text(
                "AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n"
                "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n"
                "AXStaticText\t\tSet 1 of 3\t\t@32,492 338x23\n"
                "AXButton\tstage-queue-button\t0 of 2\t\t@324,793 62x37\n")
            self.assertEqual(tree_py("crop", str(shot / "03-queue.tree.txt"), "1206", "rest-pill"), (
                1, "", "no element rest-pill on 03-queue; its ids: weight-pill stage-queue-button\n"))
        finally:
            shutil.rmtree(shot, ignore_errors=True)

    def test_a_rect_wholly_off_the_screen_is_refused(self):
        self.assertEqual(tree_py("crop", BEFORE_TREE, "1206", "402", "0", "10", "10"),
                         (1, "", "@402,0 10x10 is off the 402x874 screen\n"), "it starts at the first column past the edge")

    def test_a_malformed_argument_list_is_usage(self):
        for args in [[], [BEFORE_TREE], [BEFORE_TREE, "1206"], [BEFORE_TREE, "wide", "weight-pill"],
                     [BEFORE_TREE, "1206", "1", "2", "3"], [BEFORE_TREE, "1206", "1", "2", "0", "4"],
                     [BEFORE_TREE, "1206", "1", "2", "3.5", "4"], [BEFORE_TREE, "0", "weight-pill"]]:
            with self.subTest(args=args):
                self.assertEqual(tree_py("crop", *args), (2, "", CROP_USAGE))


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
        self.evidence = Path(tempfile.mkdtemp())
        self.dir = self.evidence / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        for offset, name in enumerate(["01-before", "02-after-log"]):
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), self.dir / ("%s.tree.txt" % name))
            os.utime(self.dir / ("%s.tree.txt" % name), (offset, offset))

    def tearDown(self):
        shutil.rmtree(self.evidence, ignore_errors=True)

    def test_verify_diff_maps_shot_names_onto_the_run(self):
        code, out, err = verify_sh("diff", "01-before", "02-after-log", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())

    def test_verify_diff_lists_the_shots_when_a_name_is_wrong(self):
        code, out, err = verify_sh("diff", "01-before", "03-typo", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 1)
        self.assertIn("shots: 01-before 02-after-log", err, "capture order, so the agent can pick again")

    def test_a_png_whose_tree_never_landed_is_not_a_shot(self):
        (self.dir / "03-half.png").write_bytes(b"png")
        code, out, err = verify_sh("diff", "01-before", "03-half", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 1)
        self.assertIn("shots: 01-before 02-after-log", err, "a shot exists when its tree exists")

    def test_a_run_name_that_is_not_a_plain_name_is_refused(self):
        for run in ["../escape", "two words", "-x"]:
            code, out, err = verify_sh("diff", "01-before", "02-after-log", run=run)
            self.assertEqual(code, 2, "%r must be refused before it becomes a path: %s" % (run, err))

    def test_launch_refuses_an_unknown_fixture_before_any_simulator_is_touched(self):
        code, out, err = verify_sh("launch", "no-such-fixture", run=self.run, sim="NO-SUCH-DEVICE")
        self.assertEqual(code, 2, err)
        self.assertIn("unknown fixture: no-such-fixture", err)
        self.assertEqual(out, "", "nothing was launched")

    def test_sheet_refuses_an_argument_it_would_ignore(self):
        code, out, err = verify_sh("sheet", "02-after-log", run=self.run)
        self.assertEqual(code, 2, "sheet tiles the whole run; a stray name must not look accepted: %s" % err)
        self.assertEqual(out, "")

    def test_tap_says_usage_for_a_flag_left_without_its_value(self):
        for argv in [["tap", "--id"], ["tap", "--wait-timeout"], ["tap", "--label", "Save", "--wait-timeout"]]:
            code, out, err = verify_sh(*argv, run=self.run, sim="NO-SUCH-DEVICE")
            self.assertEqual(code, 2, "%s must print usage, not die on its own shift: %s" % (argv, err))
            self.assertIn("Usage:", err)

    def test_tap_by_id_refuses_a_wait_timeout_it_cannot_count(self):
        code, out, err = verify_sh(
            "tap", "--id", "weight-pill", "--wait-timeout", "1.5", run=self.run, sim="NO-SUCH-DEVICE")
        self.assertEqual(code, 2, "the poll budget is counted in whole seconds: %s" % err)
        self.assertIn("whole seconds", err)
        self.assertEqual(out, "", "refused before any simulator is touched")

    def test_shot_refuses_a_name_that_could_collide(self):
        for name in ["_sheet", "a.burst", "-x"]:
            code, out, err = verify_sh("shot", name, run=self.run)
            self.assertEqual(code, 2, "%s must be refused before any simulator is touched: %s" % (name, err))


FAKE_AXE = """#!/bin/sh
printf '%s\\n' "$*" >> "{dir}/calls"
case $1 in
  describe-ui)
    case "$*" in
      *--point*) cat "{dir}/point.json" ;;
      *) cat "{dir}/describe-ui.json" ;;
    esac ;;
  tap) echo "Tap completed" ;;
  *) exit 64 ;;
esac
"""
WITH_GEAR = json.loads(MINI)
WITH_GEAR[0]["pid"] = int(APP)
WITH_GEAR[0]["children"].append(json.loads(GEAR_UP))
WITH_GEAR = json.dumps(WITH_GEAR)


class VerifyTap(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        skill = self.root / ".agents" / "skills" / "verify"
        skill.mkdir(parents=True)
        for name in ["verify.sh", "tree.py"]:
            (skill / name).symlink_to(SKILL / name)
        (self.root / "scripts").mkdir()
        (self.root / "scripts" / "sim-lock.sh").symlink_to(REPO / "scripts" / "sim-lock.sh")
        axe = self.root / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        axe.write_text(FAKE_AXE.replace("{dir}", str(self.root)))
        axe.chmod(0o755)
        self.verify = skill / "verify.sh"
        self.sim = "TAP-TEST-%d" % os.getpid()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def tap(self, tree, *args, point=None):
        (self.root / "describe-ui.json").write_text(tree)
        if point is not None:
            (self.root / "point.json").write_text(point)
        env = dict(os.environ, SIM=self.sim)
        env.pop("VERIFY_RUN", None)
        done = subprocess.run(
            [str(self.verify), "tap"] + list(args), cwd=str(self.root), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        calls = self.root / "calls"
        return done.returncode, done.stdout, done.stderr, calls.read_text().splitlines() if calls.exists() else []

    def test_a_label_tree_py_refuses_is_never_tapped(self):
        self.assertEqual(self.tap(MINI, "--label", "Farmer Carry", "--wait-timeout", "0"),
                         (1, "", "off-screen: swipe it into view before tapping\n", ["describe-ui --udid %s" % self.sim]))

    def test_a_label_tree_py_resolves_is_tapped_once_at_its_centre(self):
        row = {"role": "AXButton", "AXUniqueId": "settings-developer-tools-row", "AXLabel": "Developer Tools",
               "pid": 890, "frame": {"x": 16, "y": 570, "width": 370, "height": 52}}
        self.assertEqual(self.tap(SETTINGS, "--label", "Developer Tools", "--wait-timeout", "0", point=json.dumps(row)),
                         (0, "Tap completed\n", "", ["describe-ui --udid %s" % self.sim,
                                                      "describe-ui --udid %s --point 201,596" % self.sim,
                                                      "tap --udid %s -x 201 -y 596" % self.sim]))

    def test_a_target_on_top_at_its_centre_is_tapped_after_the_point_read(self):
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=GEAR_UP),
                         (0, "Tap completed\n", "", ["describe-ui --udid %s" % self.sim,
                                                      "describe-ui --udid %s --point 356,87" % self.sim,
                                                      "tap --udid %s -x 356 -y 87" % self.sim]))

    def test_a_covered_target_is_never_tapped(self):
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=GEAR_HIDDEN),
                         (1, "", GEAR_COVERED, ["describe-ui --udid %s" % self.sim,
                                                "describe-ui --udid %s --point 356,87" % self.sim]),
                         "the tree still had the gear; the point read found the header text in its place")

    def launched(self, pid):
        state = Path("/tmp/workout-verify-%s" % self.sim)
        state.mkdir(exist_ok=True)
        self.addCleanup(shutil.rmtree, str(state), True)
        (state / "pid").write_text(pid + "\n")

    def test_a_prompt_from_another_process_over_the_launched_app_is_never_tapped(self):
        self.launched(APP)
        prompt = {"role": "AXButton", "AXLabel": "Allow", "pid": 111, "frame": {"x": 0, "y": 0, "width": 402, "height": 874}}
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=json.dumps(prompt)),
                         (1, "", "covered: at 356,87 the screen has AXButton Allow @0,0 402x874, "
                                 "not AXButton session-controls-settings-button" + COVERED,
                          ["describe-ui --udid %s" % self.sim, "describe-ui --udid %s --point 356,87" % self.sim]))

    def test_a_home_screen_icon_is_tapped_by_the_tree_alone_while_the_app_is_away_and_says_so(self):
        self.launched("7427")
        misread = (FIXTURES / "home-screen-icon-point.describe-ui.json").read_text()
        self.assertEqual(self.tap(HOME_SCREEN, "--id", "WorkoutTracker", "--wait-timeout", "0", point=misread),
                         (0, "Tap completed\n",
                          "not checked for cover: pid 90129 is in front, not pid 7427 that launch started, "
                          "so this tap goes by the tree alone\n",
                          ["describe-ui --udid %s" % self.sim, "tap --udid %s -x 62 -y 336" % self.sim]),
                         "live-activity.md reopens the app this way; the springboard's point read is not its tree")

    def test_with_no_launch_pid_the_check_holds_on_the_home_screen_too(self):
        misread = (FIXTURES / "home-screen-icon-point.describe-ui.json").read_text()
        self.assertEqual(self.tap(HOME_SCREEN, "--id", "WorkoutTracker", "--wait-timeout", "0", point=misread),
                         (1, "", "covered: at 62,336 the screen has AXButton Contacts @211,188 72x91, "
                                 "not AXButton WorkoutTracker" + COVERED,
                          ["describe-ui --udid %s" % self.sim, "describe-ui --udid %s --point 62,336" % self.sim]),
                         "after stop, or for an app launch did not start, nothing tells the Home Screen apart")

    def test_the_launched_app_in_front_is_checked_and_prints_no_note(self):
        self.launched(APP)
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=GEAR_HIDDEN),
                         (1, "", GEAR_COVERED, ["describe-ui --udid %s" % self.sim,
                                                "describe-ui --udid %s --point 356,87" % self.sim]))

    def test_a_coordinate_tap_still_goes_straight_to_axe(self):
        self.assertEqual(self.tap(MINI, "-x", "5", "-y", "6"),
                         (0, "Tap completed\n", "", ["tap --udid %s --wait-timeout 3 -x 5 -y 6" % self.sim]),
                         "no element is resolved, so it reports success whatever is under 5,6")

    def test_a_label_without_its_text_or_beside_an_id_is_usage(self):
        for argv in [["--label"], ["--id", "settings-sign-out-button", "--label", "Sign Out"]]:
            with self.subTest(argv=argv):
                code, out, err, calls = self.tap(SETTINGS, *argv)
                self.assertEqual((code, out, calls), (2, "", []), err)
                self.assertIn("Usage:", err)

    def test_a_label_refuses_a_wait_timeout_it_cannot_count(self):
        self.assertEqual(self.tap(SETTINGS, "--label", "Developer Tools", "--wait-timeout", "1.5"),
                         (2, "", "--wait-timeout with --id or --label is whole seconds: 1.5\n", []))


class VerifyStop(unittest.TestCase):
    def setUp(self):
        self.owner = "owner-%d" % os.getpid()
        self.next = "next-%d" % os.getpid()
        self.sim = "NO-SUCH-DEVICE-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("%s\n" % self.owner)
        (self.state / "pid").write_text("99999999\n")
        self.evidence = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.state, ignore_errors=True)
        shutil.rmtree(self.evidence, ignore_errors=True)

    def stop(self, run):
        return verify_sh("stop", run=run, sim=self.sim, evidence=self.evidence)

    def launched_with_live_activities(self):
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_ANIMATIONS\n")

    def test_stop_refuses_to_end_a_run_that_is_not_the_callers(self):
        (self.state / "pid").write_text("%d\n" % os.getpid())
        code, out, err = self.stop("issue-660")
        self.assertEqual(code, 75, "the code launch already uses for a simulator another run owns")
        self.assertIn(self.owner, err, "whose app it is about to end")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err, "the override, spelled out")
        self.assertEqual(out, "", "nothing was terminated")
        self.assertTrue((self.state / "pid").exists(), "the owner keeps the pid it recorded")

    def test_stop_ends_the_callers_own_run(self):
        self.launched_with_live_activities()
        code, out, err = self.stop(self.owner)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err, "its own stop goes on to the uninstall")
        self.assertFalse((self.state / "pid").exists(), "its own stop clears the pid it recorded")

    def test_stop_refuses_to_uninstall_a_live_activity_run_that_is_not_the_callers(self):
        self.launched_with_live_activities()
        code, out, err = self.stop(self.next)
        self.assertEqual(code, 75, "its app died, but stop would still uninstall it and end the run's Live Activity")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err)
        self.assertTrue((self.state / "args").exists(), "the owner's own stop can still uninstall")

    def test_a_dead_pid_that_stop_would_only_forget_is_not_refused(self):
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        code, out, err = self.stop(self.next)
        self.assertEqual((code, out, err), (0, "", ""))
        self.assertFalse((self.state / "pid").exists(), "no app and no Live Activity, so nothing to protect")

    def test_a_dead_pid_with_no_args_is_not_refused(self):
        code, out, err = self.stop(self.next)
        self.assertEqual(
            (code, out, err), (0, "", ""),
            "a launch cut off after its pid write recorded no opt-in, so no stop would uninstall this app",
        )
        self.assertFalse((self.state / "pid").exists())

    def test_after_the_owners_stop_the_next_runs_stop_is_not_refused(self):
        code, out, err = self.stop(self.owner)
        self.assertEqual(code, 0, err)
        code, out, err = self.stop(self.next)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "nothing launched by this tool on %s\n" % self.sim)

    def test_an_unnamed_diff_after_stop_still_reads_the_runs_shots(self):
        evidence = self.evidence / self.owner
        evidence.mkdir(parents=True, exist_ok=True)
        for name in ["01-before", "02-after-log"]:
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), evidence / ("%s.tree.txt" % name))
        self.stop(self.owner)
        code, out, err = verify_sh("diff", "01-before", "02-after-log", run=None, sim=self.sim, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())

    def test_stop_on_a_simulator_no_run_has_claimed_is_not_refused(self):
        (self.state / "run").unlink()
        self.launched_with_live_activities()
        code, out, err = self.stop("issue-660")
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err, "an app no run has claimed is nobody's")

    def test_stop_without_a_run_name_is_still_allowed(self):
        self.launched_with_live_activities()
        code, out, err = self.stop(None)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err)
        self.assertFalse(
            (self.state / "pid").exists(),
            "with no VERIFY_RUN the guard has nothing to compare against, so it steps aside and "
            "the ordinary single drive keeps working",
        )


def bundle_hash(code):
    manifest = "%s  ./WorkoutTracker.debug.dylib\n" % hashlib.sha256(code).hexdigest()
    return hashlib.sha256(manifest.encode()).hexdigest()


def digest(code):
    return bundle_hash(code)[:12]


def app_hash(app):
    lines = "".join("%s  ./%s\n" % (hashlib.sha256(f.read_bytes()).hexdigest(), f.relative_to(app))
                    for f in sorted(app.rglob("*")) if f.is_file() and f.name != "verify-stamp")
    return hashlib.sha256(lines.encode()).hexdigest()


def built_app(home, code):
    derived = home / "Library" / "Developer" / "Xcode" / "DerivedData" / "WorkoutTracker-test"
    app = derived / "Build" / "Products" / "Debug-iphonesimulator" / "WorkoutTracker.app"
    app.mkdir(parents=True)
    (app / "WorkoutTracker.debug.dylib").write_bytes(code)
    (derived / "info.plist").touch()
    return app


STUB = """#!/bin/sh
[ "$(basename "$0") $*" != "xcrun simctl list devices available -j" ] || { echo '{"devices": {"iOS-27-0": [{"udid": "{sim}"}]}}'; exit 0; }
printf '%s\\n' "$(basename "$0") $*" >> "{dir}/calls"
[ "$(basename "$0") $1 $2" != "plutil -extract WorkspacePath" ] || { echo "{project}"; exit 0; }
[ "$(basename "$0")" != xcodebuild ] || echo "** BUILD FAILED **"
[ -n "${STUB_HOLD:-}" ] || exit 1
touch "{dir}/holding"
i=0
while [ ! -f "{dir}/release" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
exit 1
"""
def fake_checkout(root):
    checkout = root / "checkout"
    skill = checkout / ".agents" / "skills" / "verify"
    skill.mkdir(parents=True)
    (checkout / "scripts").mkdir()
    for name in ["test-sim.sh", "test-log-summary.awk", "sim-lock.sh", "ensure-simulator.sh"]:
        (checkout / "scripts" / name).symlink_to(REPO / "scripts" / name)
    for name in ["verify.sh", "tree.py"]:
        (skill / name).symlink_to(SKILL / name)
    return checkout


FIXTURE_APP = [sys.executable, "-c", "import time; time.sleep(60)", "-UITEST_FIXTURE"]


class SimulatorLock(unittest.TestCase):
    def setUp(self):
        self.sim = "LOCK-TEST-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        shutil.rmtree(self.state, ignore_errors=True)
        self.stubs = Path(tempfile.mkdtemp())
        stub = STUB.replace("{dir}", str(self.stubs)).replace("{sim}", self.sim)
        for tool in ["xcodebuild", "xcrun", "npm", "plutil"]:
            (self.stubs / tool).write_text(stub.replace("{project}", str(REPO / "WorkoutTracker.xcodeproj")))
            (self.stubs / tool).chmod(0o755)
        self.path = "%s:%s" % (self.stubs, os.environ["PATH"])
        self.home = self.stubs / "home"
        self.app = built_app(self.home, b"head\n")
        self.evidence = self.stubs / "evidence"
        self.runs = []
        self.checkout = fake_checkout(self.stubs)

    def tearDown(self):
        (self.stubs / "release").touch()
        for run in self.runs:
            if run.poll() is None:
                os.killpg(run.pid, 9)
                run.wait()
            for pipe in (run.stdout, run.stderr):
                if pipe:
                    pipe.close()
        shutil.rmtree(self.stubs, ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)

    def calls(self):
        path = self.stubs / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def verify(self, *argv, run="issue-626"):
        return verify_sh(*argv, run=run, sim=self.sim, path=self.path, evidence=self.evidence, HOME=str(self.home))

    def first_words(self):
        return [call.split()[:2] for call in self.calls()]

    def spawn(self, argv, hold=False, **env):
        env = dict(os.environ, PATH=self.path, **env)
        if hold:
            env["STUB_HOLD"] = "1"
        run = subprocess.Popen(
            argv, cwd=str(REPO), env=env, start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.runs.append(run)
        return run

    def spawn_test_sim(self, hold=False):
        return self.spawn([str(self.checkout / "scripts" / "test-sim.sh"), "--sim", self.sim, "unit"], hold)

    def wait_for_hold(self, run, stub):
        for _ in range(100):
            if (self.stubs / "holding").exists():
                return run
            if run.poll() is not None:
                self.fail("exited %s before it reached %s: %s" % (run.returncode, stub, run.stderr.read()))
            time.sleep(0.1)
        self.fail("never reached %s" % stub)

    def holding_test_sim(self):
        (self.stubs / "holding").unlink(missing_ok=True)
        return self.wait_for_hold(self.spawn_test_sim(hold=True), "xcodebuild")

    def own_the_app(self, owner, argv=FIXTURE_APP):
        app = subprocess.Popen(argv, start_new_session=True)
        self.runs.append(app)
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("%s\n" % owner)
        (self.state / "pid").write_text("%d\n" % app.pid)
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        return app

    def test_launch_refuses_while_a_test_sim_run_holds_the_simulator(self):
        run = self.holding_test_sim()
        code, out, err = self.verify("launch", "session")
        self.assertEqual((code, out), (75, ""), err)
        self.assertEqual(err, (
            "%s is held by a test-sim.sh run (pid %d); wait for it to finish, or use another simulator "
            "(lsof /tmp/workout-verify-%s/lock lists every process holding it)\n"
            "app on %s unchanged: an unknown app (the simulator is not booted); this launch wanted app %s commit unknown "
            "(not built by verify.sh)\n"
        ) % (self.sim, run.pid, self.sim, self.sim, digest(b"head\n")), "names the holder, then the app left installed")
        self.assertEqual(self.calls()[1:], [
            "plutil -extract WorkspacePath raw %s" % (self.app.parents[3] / "info.plist"),
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker" % self.sim,
            "xcrun simctl list devices booted",
        ], "refused before any simulator is touched: no install, no axe install, only reads of what is installed")

    def test_test_sim_refuses_while_a_verify_run_owns_the_app(self):
        app = self.own_the_app("owner-626")
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 75, err)
        self.assertEqual(
            err,
            "a verify run owner-626 owns the app on %s (pid %d), last used 0 min ago; a claim takes it once it goes 60 min "
            "unused. If it is yours, rerun with VERIFY_RUN=owner-626 or run: SIM=%s VERIFY_RUN=owner-626 "
            "%s/.agents/skills/verify/verify.sh stop, else use another simulator\n" % (self.sim, app.pid, self.sim, self.checkout),
            "names the verify run and its app, and a stop that frees this simulator from any directory",
        )
        self.assertEqual(self.calls(), [], "refused before xcodebuild")

    def test_a_pid_another_process_reused_does_not_hold_the_simulator(self):
        self.own_the_app("owner-626", ["sleep", "60"])
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 65, "went ahead to the stub build, which failed: %s" % err)
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]])

    def test_test_sim_refuses_while_a_launch_is_under_way(self):
        launch = self.spawn([str(SKILL / "verify.sh"), "launch", "session"], hold=True,
                            SIM=self.sim, VERIFY_RUN="issue-626", HOME=str(self.home))
        self.wait_for_hold(launch, "xcrun simctl bootstatus")
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 75, err)
        self.assertIn("verify.sh launch (pid %d)" % launch.pid, err, "names the launch that holds it")
        self.assertEqual(self.first_words(), [["plutil", "-extract"], ["xcrun", "simctl"]],
                         "the launch got as far as its boot wait, and test-sim.sh ran no xcodebuild")

    def test_stop_refuses_to_uninstall_while_a_test_sim_run_holds_the_simulator(self):
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("owner-626\n")
        (self.state / "pid").write_text("99999999\n")
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_ANIMATIONS\n")
        run = self.holding_test_sim()
        code, out, err = self.verify("stop", run="owner-626")
        self.assertEqual(code, 75, "the uninstall would remove the app under test: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
        self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]], "no xcrun call")
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ["args", "lock", "pid", "run"],
                         "a later stop can still uninstall")
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        code, out, err = self.verify("stop", run="owner-626")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.calls()[-1], "xcrun simctl uninstall %s com.sunnypatel.WorkoutTracker" % self.sim)
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ["lock", "run"])

    def test_a_test_sim_run_holds_the_simulator_until_it_exits(self):
        run = self.holding_test_sim()
        self.assertEqual(self.verify("launch", "session")[0], 75)
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        self.assertEqual(run.returncode, 65, "the stub build failed, so the run ended")
        code, out, err = self.verify("launch", "session")
        self.assertNotEqual(code, 75, err)
        self.assertNotIn("test-sim.sh", err)

    def test_a_killed_test_sim_run_does_not_hold_the_simulator(self):
        killed = self.holding_test_sim()
        os.killpg(killed.pid, 9)
        killed.wait()
        run = self.holding_test_sim()
        code, out, err = self.verify("launch", "session")
        self.assertEqual(code, 75, err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "the live run holds it, not the killed one")

    def test_a_dead_verify_app_does_not_hold_the_simulator(self):
        self.own_the_app("owner-626")
        (self.state / "pid").write_text("99999999\n")
        run = self.holding_test_sim()
        code, out, err = self.verify("launch", "session")
        self.assertEqual(code, 75, "the test-sim.sh run went ahead and holds it now: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err)

    def test_shot_and_burst_refuse_while_a_test_sim_run_holds_the_simulator(self):
        run = self.holding_test_sim()
        name = "issue-626-%d" % os.getpid()
        evidence = self.evidence / name
        for argv in [["shot", "01-mid-test"], ["burst", "log-transition"]]:
            code, out, err = self.verify(*argv, run=name)
            self.assertEqual(code, 75, "%s would record the test run's screen: %s" % (argv[0], err))
            self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
            self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]],
                         "refused before any simulator is touched: no xcrun, no axe install")
        self.assertFalse(evidence.exists(), "no evidence directory for shots that were never taken")
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        for argv in [["shot", "02-after-test"], ["burst", "log-transition"]]:
            code, out, err = self.verify(*argv, run=name)
            self.assertNotEqual(code, 75, "%s goes ahead once the test run is over: %s" % (argv[0], err))
            self.assertNotIn("is held", err)

    def test_the_xcodebuild_of_a_killed_test_sim_run_holds_the_simulator_until_it_exits(self):
        run = self.holding_test_sim()
        os.kill(run.pid, 9)
        run.wait()
        code, out, err = self.verify("launch", "session")
        self.assertEqual(code, 75, "its xcodebuild still drives the simulator: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "the run that started it")
        self.assertIn("lsof /tmp/workout-verify-%s/lock" % self.sim, err, "finds the xcodebuild its dead pid hides")
        self.assertEqual(out, "")
        (self.stubs / "release").touch()
        for _ in range(50):
            code, out, err = self.verify("launch", "session")
            if code != 75:
                break
            time.sleep(0.1)
        self.assertNotEqual(code, 75, "the xcodebuild exited, so nothing holds the simulator: %s" % err)
        self.assertRegex((self.state / "lock").read_text(), r"^verify\.sh launch \(pid \d+\)\n$", "the launch took it")


BOOT_STUB = """#!/bin/sh
lock=/tmp/workout-verify-{sim}/lock
if [ "$*" = "simctl list devices available -j" ]; then
  echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone 17 Pro", "udid": "{sim}", "state": "Shutdown"}]}}'
  exit 0
fi
held=$(python3 -c 'import fcntl, sys
try: fcntl.flock(open(sys.argv[1]), fcntl.LOCK_SH | fcntl.LOCK_NB)
except FileNotFoundError: print("free")
except BlockingIOError: print("held by " + open(sys.argv[1]).read().strip())
else: print("free")' "$lock")
printf '%s, lock %s\\n' "$(basename "$0") $*" "$held" >> "{dir}/calls"
case "$(basename "$0") $2" in
  "plutil WorkspacePath") echo "{project}" ;;
  "xcrun bootstatus")
    if [ -n "${STUB_HOLD:-}" ]; then echo $$ > "{dir}/holding"; exec sleep 30; fi
    exit "${STUB_BOOTSTATUS:-1}" ;;
  "xcrun list"|"xcrun boot") ;;
  *) exit 1 ;;
esac
"""
NOT_BOOTED = ("simulator %s did not boot\n"
              "app on %s unchanged: an unknown app (the simulator is not booted); this launch wanted app %s commit unknown "
              "(not built by verify.sh)\n")


class LaunchBoots(unittest.TestCase):
    def setUp(self):
        self.sim = "BOOT-TEST-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        shutil.rmtree(self.state, ignore_errors=True)
        self.home = Path(tempfile.mkdtemp())
        self.plist = built_app(self.home, b"head\n").parents[3] / "info.plist"
        self.stubs = self.home / "bin"
        self.stubs.mkdir()
        stub = BOOT_STUB.replace("{sim}", self.sim).replace("{dir}", str(self.stubs))
        stub = stub.replace("{project}", str(REPO / "WorkoutTracker.xcodeproj"))
        for tool in ["xcodebuild", "xcrun", "npm", "plutil"]:
            (self.stubs / tool).write_text(stub)
            (self.stubs / tool).chmod(0o755)
        self.runs = []

    def tearDown(self):
        for run in self.runs:
            if run.poll() is None:
                os.killpg(run.pid, 9)
                run.wait()
            for pipe in (run.stdout, run.stderr):
                pipe.close()
        shutil.rmtree(self.home, ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)

    def spawn(self, **env):
        env = dict(os.environ, HOME=str(self.home), PATH="%s:%s" % (self.stubs, os.environ["PATH"]),
                   VERIFY_RUN="issue-676", VERIFY_EVIDENCE=str(self.home / "evidence"), SIM=self.sim, **env)
        run = subprocess.Popen(
            [str(SKILL / "verify.sh"), "launch", "session"], cwd=str(REPO), env=env, start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.runs.append(run)
        return run

    def launch(self, **env):
        (self.stubs / "calls").unlink(missing_ok=True)
        run = self.spawn(**env)
        out, err = run.communicate(timeout=30)
        calls = self.stubs / "calls"
        return run, calls.read_text().splitlines() if calls.exists() else [], (run.returncode, out, err)

    def test_launch_waits_on_the_boot_under_its_lock_and_installs_nothing_when_it_fails(self):
        run, calls, result = self.launch()
        holder = "lock held by verify.sh launch (pid %d)" % run.pid
        self.assertEqual(calls, [
            "plutil -extract WorkspacePath raw %s, lock free" % self.plist,
            "xcrun simctl boot %s, %s" % (self.sim, holder),
            "xcrun simctl bootstatus %s -b, %s" % (self.sim, holder),
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker, %s" % (self.sim, holder),
            "xcrun simctl list devices booted, %s" % holder,
        ], "the app is found before the claim; the simulator is admitted, booted and waited on while the launch holds it, "
           "and never installed to")
        self.assertEqual(result, (70, "", NOT_BOOTED % (self.sim, self.sim, digest(b"head\n"))))
        self.assertRegex((self.home / "evidence" / "issue-676" / "launches.txt").read_text(),
                         r"^\S+ launch refused: app on %s unchanged: an unknown app" % self.sim)

    def test_a_boot_wait_that_ends_with_the_simulator_down_installs_nothing(self):
        run, calls, result = self.launch(STUB_BOOTSTATUS="0")
        self.assertEqual(calls[2:], [
            "xcrun simctl bootstatus %s -b, lock held by verify.sh launch (pid %d)" % (self.sim, run.pid),
            "xcrun simctl list devices booted, lock held by verify.sh launch (pid %d)" % run.pid,
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker, lock held by verify.sh launch (pid %d)"
            % (self.sim, run.pid),
            "xcrun simctl list devices booted, lock held by verify.sh launch (pid %d)" % run.pid,
        ], "bootstatus exits 0 when a shutdown ends the boot, so the launch reads the state before it installs")
        self.assertEqual(result, (70, "", NOT_BOOTED % (self.sim, self.sim, digest(b"head\n"))))

    def test_a_launch_killed_during_its_boot_wait_frees_the_simulator_at_once(self):
        killed = self.spawn(STUB_HOLD="1")
        for _ in range(100):
            if (self.stubs / "holding").exists() or killed.poll() is not None:
                break
            time.sleep(0.1)
        self.assertTrue((self.stubs / "holding").exists(), "the launch never reached its boot wait")
        os.kill(killed.pid, 9)
        killed.wait()
        boot_wait = int((self.stubs / "holding").read_text())
        self.addCleanup(os.kill, boot_wait, 9)
        run, calls, result = self.launch()
        os.kill(boot_wait, 0)
        self.assertEqual(result, (70, "", NOT_BOOTED % (self.sim, self.sim, digest(b"head\n"))),
                         "the next launch takes the simulator while the killed one's boot wait still runs")


PICK_STUB = """#!/bin/sh
printf '%s\\n' "$(basename "$0") $*" >> "{dir}/calls"
case "$(basename "$0") $*" in
  "xcrun simctl list devices available -j") cat "{dir}/devices.json" ;;
  "xcrun simctl list devices booted") echo "    iPhone 17 Pro (${STUB_BOOTED:-}) (Booted)" ;;
  "xcrun simctl list -j") cat "{dir}/catalog.json" ;;
  "xcrun simctl create "*)
    python3 -c 'import json, sys
from pathlib import Path
stubs, name, runtime, udid = sys.argv[1:]
for listing in ("devices.json", "catalog.json"):
    path = Path(stubs, listing)
    machine = json.loads(path.read_text())
    machine["devices"].setdefault(runtime, []).append(
        {"name": name, "udid": udid, "state": "Shutdown", "isAvailable": True})
    path.write_text(json.dumps(machine))' "{dir}" "$3" "$5" {created}
    echo {created} ;;
  "xcrun simctl boot "*) ;;
  "xcrun simctl install "*) rm -rf "{dir}/container"; mkdir "{dir}/container"; cp -R "$4" "{dir}/container/" ;;
  "xcrun simctl get_app_container "*) [ -d "{dir}/container/WorkoutTracker.app" ] && echo "{dir}/container/WorkoutTracker.app" ;;
  "xcrun simctl bootstatus "*) exit "${STUB_BOOTSTATUS:-1}" ;;
  "xcrun simctl launch "*) echo "com.sunnypatel.WorkoutTracker: 4121" ;;
  "xcodebuild "*) echo "** BUILD FAILED **" ; exit 65 ;;
  "plutil -extract WorkspacePath"*) echo "{project}" ;;
  "axe describe-ui "*) cat "{dir}/describe-ui.json" ;;
  *) exit 1 ;;
esac
"""
IOS_26_5 = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "isAvailable": True}
IOS_27_0 = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": True}
PRO = {"name": "iPhone 17 Pro", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}
PRO_MAX = {"name": "iPhone 17 Pro Max", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"}
AIR = {"name": "iPhone Air", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Air"}
CREATE_PRO = ("xcrun simctl create iPhone 17 Pro com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "
              "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
SIM_UNSET = (
    "SIM is not set. verify.sh drives only the simulator you name, because the stock iPhone 17 Pro is shared and "
    "another agent's app may be on it (issue 660).\n"
    "Make a lane simulator once and pass it on every call:\n"
    "  export SIM=$(xcrun simctl create LANE_NAME \"iPhone 17 Pro\" com.apple.CoreSimulator.SimRuntime.iOS-27-0)\n"
)


def device(name, udid, state="Shutdown", available=True):
    return {"name": name, "udid": udid, "state": state, "isAvailable": available}


def pick_udid(serial):
    return "%08X-0579-4ABC-8DEF-%012X" % (os.getpid(), serial)


class SimulatorPick(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.checkout = fake_checkout(self.tmp)
        self.home = self.tmp / "home"
        self.app = built_app(self.home, b"head\n")
        self.plist = self.app.parents[3] / "info.plist"
        self.evidence = self.tmp / "evidence"
        self.stubs = self.tmp / "bin"
        self.stubs.mkdir()
        self.created = pick_udid(1)
        self.locks = [self.created]
        stub = PICK_STUB.replace("{dir}", str(self.stubs)).replace("{created}", self.created)
        stub = stub.replace("{project}", str(self.checkout / "WorkoutTracker.xcodeproj"))
        axe = self.checkout / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        for tool in [self.stubs / "xcodebuild", self.stubs / "xcrun", self.stubs / "npm", self.stubs / "plutil", axe]:
            tool.write_text(stub)
            tool.chmod(0o755)
        (self.stubs / "describe-ui.json").write_text(MINI)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        for udid in self.locks:
            shutil.rmtree("/tmp/workout-verify-%s" % udid, ignore_errors=True)

    def machine(self, runtimes, devicetypes, devices):
        self.locks += [d["udid"] for ds in devices.values() for d in ds]
        catalog = {"runtimes": runtimes, "devicetypes": devicetypes, "devices": devices}
        (self.stubs / "catalog.json").write_text(json.dumps(catalog))
        available = {runtime: [d for d in ds if d["isAvailable"]] for runtime, ds in devices.items()}
        (self.stubs / "devices.json").write_text(json.dumps({"devices": available}))

    def fresh_machine(self):
        self.machine([IOS_26_5, IOS_27_0], [PRO, PRO_MAX, AIR], {
            IOS_26_5["identifier"]: [],
            IOS_27_0["identifier"]: [device("iPhone 17 Pro Max", pick_udid(2))],
        })

    def run_script(self, argv, **env):
        (self.stubs / "calls").unlink(missing_ok=True)
        for log in self.checkout.glob(".build/*/*-build.log"):
            log.unlink()
        environment = dict(os.environ, HOME=str(self.home), PATH="%s:%s" % (self.stubs, os.environ["PATH"]),
                           VERIFY_EVIDENCE=str(self.evidence))
        environment.pop("SIM", None)
        environment.pop("VERIFY_RUN", None)
        environment.update(env)
        done = subprocess.run(
            argv, cwd=str(self.checkout), env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        calls = self.stubs / "calls"
        return done.returncode, done.stdout, done.stderr, calls.read_text().splitlines() if calls.exists() else []

    def run_test_sim(self, *argv):
        code, out, err, calls = self.run_script([str(self.checkout / "scripts" / "test-sim.sh")] + list(argv or ["visual"]))
        body, _, last = out.rstrip("\n").rpartition("\n")
        self.assertRegex(last, r"^test-sim: suite=\S+ passed=- failed=- expected=- exit=%d load1=\S+/\S+ bundle=-$" % code)
        return code, body + "\n" if body else "", err, calls

    def verify(self, *argv, **env):
        return self.run_script([str(self.checkout / ".agents" / "skills" / "verify" / "verify.sh")] + list(argv), **env)

    def failed_build(self):
        log, = self.checkout.glob(".build/*/*-build.log")
        return "** BUILD FAILED **\nbuild log: %s\n" % log

    def build_for_testing_on(self, udid):
        return ("xcodebuild build-for-testing -project %s/WorkoutTracker.xcodeproj -scheme WorkoutTracker "
                "-destination platform=iOS Simulator,id=%s -skipPackagePluginValidation -skipMacroValidation "
                "CODE_SIGNING_ALLOWED=NO" % (self.checkout, udid))

    def test_test_sim_creates_the_missing_iphone_17_pro_on_the_baseline_runtime_and_runs_on_it(self):
        self.fresh_machine()
        code, out, err, calls = self.run_test_sim()
        self.assertEqual(calls, [
            "xcrun simctl list devices available -j",
            "xcrun simctl list -j",
            CREATE_PRO,
            "xcrun simctl list devices available -j",
            "xcrun simctl list devices available -j",
            "xcrun simctl list devices available -j",
            "xcrun simctl boot %s" % self.created,
            self.build_for_testing_on(self.created),
        ], "the created simulator is picked from simctl again, admitted on the host's booted count, recounted under the admit lock, booted, and built for")
        self.assertEqual((code, out, err), (65, "", "creating iPhone 17 Pro on iOS 27.0\n" + self.failed_build()))

    def test_the_created_simulator_is_the_pair_the_visual_baselines_were_recorded_on(self):
        ci = (REPO / ".github" / "workflows" / "ci.yml").read_text()
        pinned = re.search(r"BASELINE_DEVICE: (.+)\n\s+BASELINE_RUNTIME: \"(.+)\"", ci).groups()
        self.fresh_machine()
        code, out, err, calls = self.run_test_sim()
        self.assertEqual(err.splitlines()[0], "creating %s on iOS %s" % pinned,
                         "re-recording the baselines on a new pair moves pick_sim's pair with it")

    def test_with_sim_unset_every_verify_command_that_needs_a_simulator_refuses_and_calls_no_xcrun(self):
        self.fresh_machine()
        for argv in [["build"], ["install"], ["install", "HEAD"], ["launch", "session"], ["launch", "--at", "HEAD", "session"],
                     ["doctor"], ["stop"], ["tree"], ["find", "weight-pill"], ["tap", "-x", "1", "-y", "2"],
                     ["hold", "weight-pill"], ["type", "245"], ["swipe", "up"], ["shot", "01-before"],
                     ["burst", "log-transition"], ["axe", "key", "40"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="issue-660"), (2, "", SIM_UNSET, []),
                                 "issue 660: the stock iPhone 17 Pro is never picked for you")
        self.assertFalse(self.evidence.exists(), "nothing was shot")

    def test_with_sim_unset_diff_sheet_and_crop_read_the_run_verify_run_names(self):
        run = self.evidence / "issue-660"
        run.mkdir(parents=True)
        for name in ["01-before", "02-after-log"]:
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), run / ("%s.tree.txt" % name))
        diff = (FIXTURES / "01-before--02-after-log.diff.txt").read_text()
        self.assertEqual(self.verify("diff", "01-before", "02-after-log", VERIFY_RUN="issue-660"), (0, diff, "", []))
        verify = self.checkout / ".agents" / "skills" / "verify" / "verify.sh"
        for argv in [["diff", "01-before", "02-after-log"], ["sheet"], ["crop", "01-before", "weight-pill"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv), (1, "", (
                    "no evidence directory for this run in %s; name one: VERIFY_RUN=<run> %s %s ...\n"
                    "recent runs:\n  issue-660\n") % (self.evidence, verify, argv[0]), []),
                    "with neither SIM nor VERIFY_RUN there is no run to read, so it says to name one")

    def test_a_missing_runtime_or_device_type_fails_with_what_the_machine_has(self):
        unavailable = pick_udid(4)
        no_type = "Xcode has no iPhone 17 Pro device type. available:\n  iPhone 17 Pro Max\n  iPhone Air\n"
        machines = {
            "no iOS 27.0": ([IOS_26_5], [PRO, PRO_MAX], {IOS_26_5["identifier"]: []},
                            "no available iOS 27.0 runtime. available: 26.5\n"),
            "no iPhone 17 Pro": ([IOS_26_5, IOS_27_0], [PRO_MAX, AIR],
                                 {IOS_26_5["identifier"]: [], IOS_27_0["identifier"]: []}, no_type),
            "an unavailable iPhone 17 Pro and no type": (
                [IOS_26_5, IOS_27_0], [PRO_MAX, AIR],
                {IOS_27_0["identifier"]: [device("iPhone 17 Pro", unavailable, available=False)]}, no_type),
        }
        for machine, (runtimes, devicetypes, devices, message) in machines.items():
            with self.subTest(machine=machine):
                self.machine(runtimes, devicetypes, devices)
                code, out, err, calls = self.run_test_sim()
                self.assertEqual((code, out, err), (1, "", message))
                self.assertEqual(calls, ["xcrun simctl list devices available -j", "xcrun simctl list -j"],
                                 "nothing is created, booted, locked, or built")
                self.assertFalse(Path("/tmp/workout-verify-%s" % unavailable).exists(),
                                 "the unavailable one is never claimed")

    def test_an_existing_iphone_17_pro_is_picked_booted_first_then_newest_and_nothing_is_created(self):
        old, new = pick_udid(0x2605), pick_udid(0x2700)
        cases = [
            ("the booted one, though older", "Booted", "Shutdown",
             ["xcrun simctl list devices available -j", self.build_for_testing_on(old)]),
            ("the newest when none is booted", "Shutdown", "Shutdown",
             ["xcrun simctl list devices available -j", "xcrun simctl list devices available -j",
              "xcrun simctl boot %s" % new, self.build_for_testing_on(new)]),
        ]
        for case, old_state, new_state, after_pick in cases:
            with self.subTest(case):
                self.machine([IOS_26_5, IOS_27_0], [PRO], {
                    IOS_26_5["identifier"]: [device("iPhone 17 Pro", old, old_state)],
                    IOS_27_0["identifier"]: [device("iPhone 17 Pro", new, new_state)],
                })
                code, out, err, calls = self.run_test_sim()
                self.assertEqual(calls, ["xcrun simctl list devices available -j"] + after_pick)
                self.assertEqual((code, out, err), (65, "", self.failed_build()))

    def test_a_lowercase_sim_is_the_simulator_simctl_spells_in_capitals(self):
        udid = pick_udid(3)
        self.locks.append(udid)
        state = Path("/tmp/workout-verify-%s" % udid)
        state.mkdir(parents=True, exist_ok=True)
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        (state / "run").write_text("owner-579\n")
        (state / "pid").write_text("%d\n" % app.pid)
        self.machine([IOS_27_0], [PRO], {IOS_27_0["identifier"]: [device("iPhone 17 Pro", udid)]})
        code, out, err, calls = self.run_test_sim("--sim", udid.lower(), "unit")
        self.assertEqual((code, out, err), (75, "", (
            "a verify run owner-579 owns the app on %s (pid %d), last used 0 min ago; a claim takes it once it goes 60 min "
            "unused. If it is yours, rerun with VERIFY_RUN=owner-579 or run: SIM=%s VERIFY_RUN=owner-579 "
            "%s/.agents/skills/verify/verify.sh stop, else use another simulator\n") % (udid, app.pid, udid, self.checkout)),
            "the lock is keyed by the one spelling, so a case-sensitive /tmp cannot split it")
        self.assertEqual(calls, ["xcrun simctl list devices available -j"])

    def test_a_lowercase_sim_launches_on_the_simulator_simctl_spells_in_capitals(self):
        udid = pick_udid(3)
        self.machine([IOS_27_0], [PRO], {IOS_27_0["identifier"]: [device("iPhone 17 Pro", udid)]})
        code, out, err, calls = self.verify("launch", "session", SIM=udid.lower(), VERIFY_RUN="issue-579",
                                            STUB_BOOTSTATUS="0", STUB_BOOTED=udid)
        self.assertEqual((code, out, err), (0, "launched session as pid 4121 on %s\n"
                                               "app %s commit unknown (not built by verify.sh)\n"
                                               "evidence %s/issue-579\n" % (udid, digest(b"head\n"), self.evidence), ""),
                         "simctl lists it booted in capitals")
        self.assertEqual(calls, [
            "xcrun simctl list devices available -j",
            "plutil -extract WorkspacePath raw %s" % self.plist,
            "xcrun simctl list devices available -j",
            "xcrun simctl list devices available -j",
            "xcrun simctl boot %s" % udid,
            "xcrun simctl bootstatus %s -b" % udid,
            "xcrun simctl list devices booted",
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker" % udid,
            "xcrun simctl install %s %s" % (udid, self.app),
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker" % udid,
            "xcrun simctl spawn %s defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled" % udid,
            "xcrun simctl launch --terminate-running-process %s com.sunnypatel.WorkoutTracker -UITEST_FIXTURE "
            "-UITEST_SESSION -UITEST_FULL_BLOCK -UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_LIVE_ACTIVITIES" % udid,
            "axe describe-ui --udid %s" % udid,
        ])


SYSCTL_REFUSING_ALL_BUT_THE_SUITES_KNOBS = "#!/bin/sh\necho '{ 500.00 500.00 500.00 }'\n"

LANE_STUB = """#!/bin/sh
tool=$(basename "$0")
printf '%s\\n' "$tool $*" >> "{dir}/calls"
case "$tool $1 $2" in
  "plutil -extract WorkspacePath") echo "{project}" ;;
  "xcrun simctl install")
    [ -z "${STUB_INSTALL_FAIL:-}" ] || exit 1
    [ -z "${STUB_STALE_INSTALL:-}" ] || [ ! -d "{dir}/containers/$3/WorkoutTracker.app" ] || exit 0
    rm -rf "{dir}/containers/$3"
    mkdir -p "{dir}/containers/$3"
    cp -R "$4" "{dir}/containers/$3/"
    [ -z "${STUB_TAMPER:-}" ] || printf x >> "{dir}/containers/$3/WorkoutTracker.app/WorkoutTracker.debug.dylib" ;;
  "xcrun simctl uninstall") rm -rf "{dir}/containers/$3" ;;
  "xcrun simctl get_app_container")
    [ -d "{dir}/containers/$3/WorkoutTracker.app" ] || exit 1
    echo "{dir}/containers/$3/WorkoutTracker.app" ;;
  "xcrun simctl bootstatus") ;;
  "xcrun simctl list")
    if [ "$4" = available ]; then echo "{\\"devices\\": {\\"iOS-27-0\\": [{\\"udid\\": \\"${STUB_AVAILABLE:-$SIM}\\"}]}}"
    else echo "    lane ($SIM) (Booted)"
    fi ;;
  "xcrun simctl launch") echo "com.sunnypatel.WorkoutTracker: 4121" ;;
  "xcrun simctl spawn")
    case "$4 $5" in
      "defaults read")
        [ -f "{dir}/minimization" ] || { echo "The domain/default pair of ($6, $7) does not exist" >&2; exit 1; }
        cat "{dir}/minimization" ;;
      "defaults write") echo 0 > "{dir}/minimization" ;;
    esac ;;
  "xcrun simctl io")
    out=$8
    trap 'echo INT >> "{dir}/signals"; touch "{dir}/stopped"; echo "mp4 ${STUB_MARK:-}" > "$out"; exit 0' INT
    trap 'echo TERM >> "{dir}/signals"; exit 143' TERM
    sleep 0.2
    if [ -z "${STUB_NEVER_STARTS:-}" ]; then
      echo "Recording started" >> "{dir}/calls"
      echo "Recording started" >&2
    fi
    i=0
    while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    exit 1 ;;
  "xcodebuild build -project")
    project=$3 derived=$HOME/Library/Developer/Xcode/DerivedData/WorkoutTracker-test
    while [ $# -gt 0 ]; do [ "$1" != -derivedDataPath ] || derived=$2; shift; done
    if [ -n "${STUB_BUILD_HOLD:-}" ]; then
      touch "{dir}/building"
      i=0
      while [ ! -f "{dir}/release" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    fi
    [ -z "${STUB_BUILD_FAIL:-}" ] || { echo "error: stub compile error"; echo "** BUILD FAILED **"; exit 65; }
    app=$derived/Build/Products/Debug-iphonesimulator/WorkoutTracker.app
    mkdir -p "$app"
    cat "$(dirname "$project")/App/Main.swift" > "$app/WorkoutTracker.debug.dylib" ;;
  "axe describe-ui --udid") cat "{dir}/describe-ui.json" ;;
  "axe "*) exit "${STUB_AXE_EXIT:-0}" ;;
  *) exit 1 ;;
esac
"""
KEYBOARD = ("AXe keyboard input hides the software keyboard in this app until its next launch (issue 700); "
            "the preference that would keep it hidden after that is reset\n")


class Lane(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        (self.tmp / "gitconfig").touch()
        self.env = dict(os.environ, HOME=str(self.tmp / "home"), PATH="%s:%s" % (self.tmp / "bin", os.environ["PATH"]),
                        GIT_CONFIG_GLOBAL=str(self.tmp / "gitconfig"), GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="lane", GIT_AUTHOR_EMAIL="lane@example.com",
                        GIT_COMMITTER_NAME="lane", GIT_COMMITTER_EMAIL="lane@example.com", WORKOUT_ADMIT_WAIT="0")
        for name in ["SIM", "VERIFY_RUN", "VERIFY_EVIDENCE", "VERIFY_LIVE_ACTIVITIES"]:
            self.env.pop(name, None)
        self.checkout = self.tmp / "checkout"
        self.git("init", "-q", "-b", "main", str(self.checkout), cwd=self.tmp)
        for path, text in [("App/Main.swift", "v1\n"), ("Sources/WorkoutTracker/Model.swift", ""),
                           ("WorkoutShared/Shared.swift", ""), ("WorkoutWidgets/Widget.swift", ""),
                           ("WorkoutTracker.xcodeproj/project.pbxproj", ""), ("Package.swift", ""),
                           ("Package.resolved", ""), (".gitignore", "Secrets.xcconfig\n.agents/\nscripts/\n.build/\n.claude/\n")]:
            (self.checkout / path).parent.mkdir(parents=True, exist_ok=True)
            (self.checkout / path).write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "v1")
        self.a = self.git("rev-parse", "HEAD")
        self.edit("v2\n")
        self.git("commit", "-q", "-am", "v2")
        self.b = self.git("rev-parse", "HEAD")
        self.verify_path = self.link_verify(self.checkout)
        (self.checkout / "Secrets.xcconfig").write_text("")
        derived = self.tmp / "home" / "Library" / "Developer" / "Xcode" / "DerivedData" / "WorkoutTracker-test"
        derived.mkdir(parents=True)
        (derived / "info.plist").touch()
        self.built = derived / "Build" / "Products" / "Debug-iphonesimulator" / "WorkoutTracker.app"
        self.cache = self.checkout / ".claude" / "work" / "app-cache"
        stub = LANE_STUB.replace("{dir}", str(self.tmp)).replace("{project}", str(self.checkout / "WorkoutTracker.xcodeproj"))
        axe = self.checkout / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        (self.tmp / "bin").mkdir()
        for tool in [self.tmp / "bin" / "xcrun", self.tmp / "bin" / "xcodebuild", self.tmp / "bin" / "plutil",
                     self.tmp / "bin" / "npm", axe]:
            tool.write_text(stub)
            tool.chmod(0o755)
        (self.tmp / "bin" / "sysctl").write_text(SYSCTL_REFUSING_ALL_BUT_THE_SUITES_KNOBS)
        (self.tmp / "bin" / "sysctl").chmod(0o755)
        (self.tmp / "describe-ui.json").write_text(MINI)
        self.sim = "LANE-%d" % os.getpid()
        self.other_sim = "LANE-%d-B" % os.getpid()
        for udid in [self.sim, self.other_sim]:
            shutil.rmtree("/tmp/workout-verify-%s" % udid, ignore_errors=True)
            self.addCleanup(shutil.rmtree, "/tmp/workout-verify-%s" % udid, True)

    def git(self, *args, cwd=None):
        done = subprocess.run(["git"] + list(args), cwd=str(cwd or self.checkout), env=self.env, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        return done.stdout.strip()

    def link_verify(self, checkout):
        skill = checkout / ".agents" / "skills" / "verify"
        skill.mkdir(parents=True)
        for name in ["verify.sh", "tree.py", "take.py"]:
            (skill / name).symlink_to(SKILL / name)
        (checkout / "scripts").mkdir()
        for name in ["sim-lock.sh", "bootstrap-xcode-worktree.sh"]:
            (checkout / "scripts" / name).symlink_to(REPO / "scripts" / name)
        return skill / "verify.sh"

    def edit(self, code):
        (self.checkout / "App" / "Main.swift").write_text(code)

    def environment(self, env):
        environment = dict(self.env, SIM=self.sim)
        environment.update(env)
        return environment

    def verify(self, *argv, verify=None, **env):
        (self.tmp / "calls").unlink(missing_ok=True)
        done = subprocess.run([str(verify or self.verify_path)] + list(argv), cwd=str(self.checkout),
                              env=self.environment(env), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        return done.returncode, done.stdout, done.stderr

    def calls(self):
        calls = self.tmp / "calls"
        return calls.read_text().splitlines() if calls.exists() else []

    def own_the_app(self, owner):
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        state = Path("/tmp/workout-verify-%s" % self.sim)
        state.mkdir(parents=True, exist_ok=True)
        (state / "run").write_text("%s\n" % owner)
        (state / "pid").write_text("%d\n" % app.pid)
        return app

    def evidence(self, lane, run):
        return self.checkout / ".claude" / "work" / "evidence" / lane / run

    def launched(self, line, run="lane-1", lane="main"):
        return "launched session as pid 4121 on %s\n%s\nevidence %s\n" % (self.sim, line, self.evidence(lane, run))

    def worktree_build(self, code, commit, dirty=""):
        return "app %s commit %s%s (this worktree's build)" % (digest(code), commit[:8], dirty)

    def cached_build(self, code, commit):
        return "app %s commit %s (cached build)" % (digest(code), commit[:8])

    def building(self, commit):
        return ("building %s into the app cache at %s (under a minute to a few; give the call a 10 min timeout)\n"
                "xcode-worktree-bootstrap: copied Secrets.xcconfig from main worktree\n" % (commit[:8], self.cache))


class InstalledIdentity(Lane):
    def test_build_stamps_the_app_and_launch_prints_its_hash_and_commit(self):
        self.assertEqual(self.verify("build"), (0, "built %s\n%s\n" % (self.built, self.worktree_build(b"v2\n", self.b)), ""))
        self.assertEqual((self.built / "verify-stamp").read_text(), "commit=%s\ndirty=0\norigin=%s\ncode_sha256=%s\n"
                         % (self.b, self.checkout, bundle_hash(b"v2\n")))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"),
                         (0, self.launched(self.worktree_build(b"v2\n", self.b)), ""))
        self.assertRegex((self.evidence("main", "lane-1") / "launches.txt").read_text(),
                         r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d session %s on %s from %s\n$" % (
                             re.escape(self.worktree_build(b"v2\n", self.b)), self.sim, re.escape(str(self.checkout))),
                         "the evidence names its binary after the worktree and the simulator are gone")

    def test_only_an_edit_to_what_the_app_compiles_marks_the_build_dirty(self):
        (self.checkout / "decisions.tsv").write_text("an untracked file at the root\n")
        self.assertEqual(self.verify("build")[1].splitlines()[1], self.worktree_build(b"v2\n", self.b))
        self.edit("v3\n")
        self.assertEqual(self.verify("build")[1].splitlines()[1], self.worktree_build(b"v3\n", self.b, "-dirty"))

    def test_a_stamp_whose_code_hash_no_longer_matches_reads_commit_unknown(self):
        self.verify("build")
        (self.built / "WorkoutTracker.debug.dylib").write_bytes(b"rebuilt by Xcode\n")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (0, self.launched(
            "app %s commit unknown (not built by verify.sh)" % digest(b"rebuilt by Xcode\n")), ""),
            "the hash is the identity; a stamp that does not describe these bytes vouches for nothing")

    def test_a_runs_own_relaunch_that_would_replace_a_cached_build_refuses_before_it_takes_anything_over(self):
        self.verify("build")
        self.assertEqual(self.verify("install", self.a)[0], 0)
        app = self.own_the_app("ui12")
        (Path("/tmp/workout-verify-%s" % self.sim) / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION\n")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12"), (65, "", (
            "{sim} holds {cached}, and this launch would replace it with {wanted}. To run the cached build: launch --at "
            "{a8} session. To replace it: install, then launch.\n").format(
                sim=self.sim, cached=self.cached_build(b"v1\n", self.a), wanted=self.worktree_build(b"v2\n", self.b),
                a8=self.a[:8])), "a run that had Live Activities on is not uninstalled, and no takeover is announced")
        self.assertEqual([call for call in self.calls() if " install" in call or "uninstall" in call], [])
        self.assertIsNone(app.poll(), "the run's app still runs")

    def test_a_lock_refusal_names_the_app_it_left_installed_and_the_one_it_wanted(self):
        self.verify("build")
        self.assertEqual(self.verify("install", self.a)[0], 0)
        app = self.own_the_app("owner-1")
        code, out, err = self.verify("launch", "session", VERIFY_RUN="lane-1")
        self.assertEqual((code, out), (75, ""), err)
        self.assertEqual(err, (
            "a verify run owner-1 owns the app on {sim} (pid {pid}), last used 0 min ago; a claim takes it once it goes "
            "60 min unused. If it is yours, rerun with VERIFY_RUN=owner-1 or run: SIM={sim} VERIFY_RUN=owner-1 "
            "{checkout}/.agents/skills/verify/verify.sh stop, else use another simulator\n"
            "app on {sim} unchanged: {installed}; this launch wanted {wanted}\n"
        ).format(sim=self.sim, pid=app.pid, checkout=self.checkout, installed=self.cached_build(b"v1\n", self.a),
                 wanted=self.worktree_build(b"v2\n", self.b)), "a driver that drops the first line still reads the second")
        self.assertNotIn("xcrun simctl install", " ".join(self.calls()))

    def test_installed_bytes_that_differ_from_the_build_after_a_reinstall_exit_70_naming_both(self):
        self.verify("build")
        tampered = "app %s commit unknown (not built by verify.sh)" % digest(b"v2\nx")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_TAMPER="1"), (70, "", (
            "after simctl install, {sim} holds {tampered}, not {wanted}; uninstalling it and installing once more\n"
            "after simctl install, {sim} holds {tampered}, not {wanted} that this launch installed from {built}\n"
        ).format(sim=self.sim, tampered=tampered, wanted=self.worktree_build(b"v2\n", self.b), built=self.built)))
        self.assertEqual([c for c in self.calls() if c.startswith(("xcrun simctl install", "xcrun simctl uninstall"))], [
            "xcrun simctl install %s %s" % (self.sim, self.built),
            "xcrun simctl uninstall %s com.sunnypatel.WorkoutTracker" % self.sim,
            "xcrun simctl install %s %s" % (self.sim, self.built),
        ], "one reinstall, then the refusal")
        self.assertNotIn("xcrun simctl launch", " ".join(self.calls()), "the wrong bytes are never launched")

    def test_an_install_that_leaves_the_old_bytes_is_uninstalled_and_installed_once_more(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 0)
        self.edit("v3\n")
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_STALE_INSTALL="1"), (
            0, self.launched(self.worktree_build(b"v3\n", self.b, "-dirty")),
            "after simctl install, %s holds app %s commit %s (an earlier build of this worktree), not %s; uninstalling it "
            "and installing once more\n" % (self.sim, digest(b"v2\n"), self.b[:8],
                                             self.worktree_build(b"v3\n", self.b, "-dirty"))))
        self.assertEqual(self.verify("doctor")[1].splitlines()[1],
                         "ok   installed %s" % self.worktree_build(b"v3\n", self.b, "-dirty"))

    def test_a_file_outside_the_dylib_is_part_of_the_apps_identity(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        (self.built / "Assets.car").write_bytes(b"a new colour\n")
        self.assertEqual(self.verify("doctor")[1].splitlines()[1], (
            "FAIL installed app %s commit %s (an earlier build of this worktree) is not this worktree's build, "
            "app %s commit unknown (run: %s install)") % (digest(b"v2\n"), self.b[:8],
                                                          app_hash(self.built)[:12], self.verify_path))

    def test_a_failed_simctl_install_says_so_once_and_names_what_is_there(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_INSTALL_FAIL="1"), (70, "", (
            "simctl install failed, so %s holds nothing installed, not %s\n") % (self.sim, self.worktree_build(b"v2\n", self.b))))

    def test_at_after_the_fixture_is_refused_instead_of_passed_to_the_app(self):
        self.assertEqual(self.verify("launch", "session", "--at", self.a, VERIFY_RUN="lane-1"),
                         (2, "", "--at goes before the fixture: launch --at COMMIT session\n"))
        self.assertEqual(self.calls(), [])

    def test_a_sim_no_simulator_answers_to_is_refused_before_any_build(self):
        self.assertEqual(self.verify("build", STUB_AVAILABLE="SOMEONE-ELSE"), (2, "", (
            "no available simulator %s; xcrun simctl list devices available lists them\n") % self.sim))
        self.assertEqual(self.calls(), ["xcrun simctl list devices available -j"])

    def test_a_bare_launch_over_a_cached_build_refuses_and_launch_at_runs_it(self):
        self.verify("build")
        self.assertEqual(self.verify("install", self.a[:8])[:2], (0, self.cached_build(b"v1\n", self.a) + "\n"))
        cached, head = self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b)
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (65, "", (
            "{sim} holds {cached}, and this launch would replace it with {head}. To run the cached build: "
            "launch --at {a8} session. To replace it: install, then launch.\n"
        ).format(sim=self.sim, cached=cached, head=head, a8=self.a[:8])))
        self.assertNotIn("xcrun simctl install", " ".join(self.calls()), "the control build stays installed")
        self.assertEqual(self.verify("launch", "--at", self.a[:8], "session", VERIFY_RUN="lane-1"), (0, self.launched(
            "%s; this worktree's build is app %s commit %s" % (cached, digest(b"v2\n"), self.b[:8])), ""))
        self.assertEqual(self.verify("install"), (0, "replaced %s\n%s\n" % (cached, head), ""),
                         "the head phase reinstalls this worktree's build on purpose")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (0, self.launched(head), ""))

    def test_a_refused_animated_launch_hints_the_animated_launch_of_the_cached_build(self):
        self.verify("build")
        self.verify("install", self.a[:8])
        cached, head = self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b)
        self.assertEqual(self.verify("launch", "--animated", "session", VERIFY_RUN="lane-1"), (65, "", (
            "{sim} holds {cached}, and this launch would replace it with {head}. To run the cached build: "
            "launch --at {a8} --animated session. To replace it: install, then launch.\n"
        ).format(sim=self.sim, cached=cached, head=head, a8=self.a[:8])))


class LaunchAnimated(Lane):
    def setUp(self):
        super().setUp()
        self.verify("build")

    def launch_call(self, flags):
        return ("xcrun simctl launch --terminate-running-process %s com.sunnypatel.WorkoutTracker -UITEST_FIXTURE "
                "-UITEST_SESSION -UITEST_FULL_BLOCK %s" % (self.sim, flags))

    def test_an_animated_launch_leaves_motion_on_and_says_so(self):
        head = self.worktree_build(b"v2\n", self.b)
        self.assertEqual(self.verify("launch", "--animated", "session", VERIFY_RUN="lane-1"), (0, (
            "launched session as pid 4121 on %s (animations on)\n%s\nevidence %s\n"
        ) % (self.sim, head, self.evidence("main", "lane-1")), ""))
        self.assertIn(self.launch_call("-UITEST_DISABLE_LIVE_ACTIVITIES"), self.calls())
        self.assertEqual((Path("/tmp/workout-verify-%s" % self.sim) / "args").read_text(),
                         "-UITEST_FIXTURE -UITEST_SESSION -UITEST_FULL_BLOCK -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        self.assertRegex((self.evidence("main", "lane-1") / "launches.txt").read_text(),
                         r"^\S+ session animated %s on %s from %s\n$" % (re.escape(head), self.sim,
                                                                         re.escape(str(self.checkout))))

    def test_a_plain_launch_still_disables_animations(self):
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 0)
        self.assertIn(self.launch_call("-UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_LIVE_ACTIVITIES"), self.calls())

    def test_animated_after_the_fixture_is_refused_instead_of_passed_to_the_app(self):
        self.assertEqual(self.verify("launch", "session", "--animated", VERIFY_RUN="lane-1"),
                         (2, "", "--animated goes before the fixture: launch --animated session\n"))
        self.assertEqual(self.calls(), [])

    def test_animated_and_at_go_in_either_order(self):
        cached = "%s; this worktree's build is app %s commit %s" % (
            self.cached_build(b"v1\n", self.a), digest(b"v2\n"), self.b[:8])
        for flags in [["--animated", "--at", self.a[:8]], ["--at", self.a[:8], "--animated"]]:
            with self.subTest(flags=flags):
                code, out, err = self.verify("launch", *(flags + ["session"]), VERIFY_RUN="lane-1")
                self.assertEqual((code, out.splitlines()[:2]),
                                 (0, ["launched session as pid 4121 on %s (animations on)" % self.sim, cached]), err)
                self.assertIn(self.launch_call("-UITEST_DISABLE_LIVE_ACTIVITIES"), self.calls())


class Doctor(Lane):
    def doctor_app_line(self):
        return self.verify("doctor")[1].splitlines()[1]

    def test_doctor_passes_this_worktrees_build_once_it_is_installed(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        code, out, err = self.verify("doctor")
        self.assertEqual(out.splitlines()[:2], ["ok   simulator %s booted" % self.sim,
                                                "ok   installed %s" % self.worktree_build(b"v2\n", self.b)])
        self.assertNotIn("sources", out, "nothing was edited after the build")

    def test_doctor_fails_an_installed_app_that_is_not_this_worktrees_build_naming_both(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        self.edit("v3\n")
        self.verify("build")
        self.assertEqual(self.doctor_app_line(), (
            "FAIL installed app %s commit %s (an earlier build of this worktree) is not this worktree's build, "
            "app %s commit %s-dirty (run: %s install)") % (digest(b"v2\n"), self.b[:8], digest(b"v3\n"), self.b[:8],
                                                          self.verify_path))

    def test_doctor_passes_a_cached_build_that_matches_its_cache_entry(self):
        self.verify("build")
        self.verify("install", self.a)
        self.assertEqual(self.doctor_app_line(), "ok   installed %s; this worktree's build is app %s commit %s"
                         % (self.cached_build(b"v1\n", self.a), digest(b"v2\n"), self.b[:8]))

    def test_doctor_fails_when_nothing_is_installed(self):
        self.verify("build")
        self.assertEqual(self.doctor_app_line(), "FAIL nothing installed on %s (run: %s launch <fixture>)"
                         % (self.sim, self.verify_path))


class AppCache(Lane):
    def entries(self):
        return sorted(p.name for p in self.cache.iterdir())

    def worktrees(self):
        return [line for line in self.git("worktree", "list", "--porcelain").splitlines() if line.startswith("worktree ")]

    def install_held_in_its_build(self, commit):
        install = subprocess.Popen([str(self.verify_path), "install", commit], cwd=str(self.checkout),
                                   env=self.environment({"STUB_BUILD_HOLD": "1"}), start_new_session=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        for _ in range(100):
            if (self.tmp / "building").exists() or install.poll() is not None:
                break
            time.sleep(0.1)
        return install

    def test_install_builds_a_commit_once_and_every_later_install_reuses_it(self):
        self.assertEqual(self.verify("install", self.a[:7]),
                         (0, self.cached_build(b"v1\n", self.a) + "\n", self.building(self.a)))
        self.assertEqual([call for call in self.calls() if call.startswith("xcodebuild")], [
            "xcodebuild build -project {c}/{a}.build/src/WorkoutTracker.xcodeproj -scheme WorkoutTracker "
            "-destination platform=iOS Simulator,id={sim} -derivedDataPath {c}/{a}.build/dd -skipPackagePluginValidation "
            "-skipMacroValidation CODE_SIGNING_ALLOWED=NO".format(c=self.cache, a=self.a, sim=self.sim)])
        self.assertEqual(self.entries(), [self.a, self.a + ".lock", "logs"],
                         "the abbreviated SHA keys the full one, and the scratch worktree and DerivedData are gone")
        self.assertEqual((self.cache / self.a / "WorkoutTracker.app" / "verify-stamp").read_text(),
                         "commit=%s\ndirty=0\norigin=cache\ncode_sha256=%s\n" % (self.a, bundle_hash(b"v1\n")))
        self.assertEqual(self.worktrees(), ["worktree %s" % self.checkout])
        self.assertEqual(self.verify("install", self.a), (0, self.cached_build(b"v1\n", self.a) + "\n", ""))
        self.assertEqual([call for call in self.calls() if call.startswith("xcodebuild")], [], "a hit builds nothing")

    def test_two_installs_of_one_commit_at_once_build_it_once(self):
        first = self.install_held_in_its_build(self.a)
        self.assertTrue((self.tmp / "building").exists(), "the first install never reached its build")
        waited = self.tmp / "second.err"
        with open(str(waited), "w") as err:
            second = subprocess.Popen([str(self.verify_path), "install", self.a], cwd=str(self.checkout),
                                      env=self.environment({"SIM": self.other_sim, "STUB_BUILD_HOLD": "1"}),
                                      start_new_session=True, stdout=subprocess.PIPE, stderr=err, universal_newlines=True)
        wait_line = "waiting for another build of %s into the app cache (lsof %s/%s.lock lists it)\n" % (
            self.a[:8], self.cache, self.a)
        for _ in range(100):
            if waited.read_text() == wait_line or second.poll() is not None:
                break
            time.sleep(0.1)
        (self.tmp / "release").touch()
        first_out, first_err = first.communicate(timeout=30)
        second_out, _ = second.communicate(timeout=30)
        self.assertEqual((first.returncode, first_out, first_err), (0, self.cached_build(b"v1\n", self.a) + "\n",
                                                                    self.building(self.a)))
        self.assertEqual((second.returncode, second_out, waited.read_text()),
                         (0, self.cached_build(b"v1\n", self.a) + "\n", wait_line))
        self.assertEqual(len([call for call in self.calls() if call.startswith("xcodebuild")]), 1)

    def test_a_failed_build_publishes_nothing_and_the_next_install_builds_it(self):
        self.assertEqual(self.verify("install", self.a, STUB_BUILD_FAIL="1"), (65, "", self.building(self.a) + (
            "error: stub compile error\n** BUILD FAILED **\nbuild log: {c}/logs/{a}.log\napp on {sim} unchanged: nothing "
            "installed; this install wanted {a8} from the app cache, and its build failed\n").format(
                c=self.cache, a=self.a, sim=self.sim, a8=self.a[:8])))
        self.assertEqual(self.entries(), [self.a + ".lock", "logs"], "no entry, no scratch")
        self.assertEqual(self.worktrees(), ["worktree %s" % self.checkout])
        self.assertEqual(self.verify("install", self.a), (0, self.cached_build(b"v1\n", self.a) + "\n", self.building(self.a)))

    def killed_build(self, commit):
        install = self.install_held_in_its_build(commit)
        self.addCleanup(install.communicate)
        self.assertTrue((self.tmp / "building").exists(), "the install never reached its build")
        os.killpg(install.pid, signal.SIGKILL)
        install.wait()
        (self.tmp / "building").unlink()
        self.assertEqual(self.entries(), [commit + ".build", commit + ".lock", "logs"])

    def test_another_commits_install_sweeps_a_killed_builds_scratch_and_worktree(self):
        self.killed_build(self.a)
        self.assertEqual(len(self.worktrees()), 2)
        self.assertEqual(self.verify("install", self.b)[0], 0)
        self.assertEqual(self.entries(), sorted([self.a + ".lock", self.b, self.b + ".lock", "logs"]))
        self.assertEqual(self.worktrees(), ["worktree %s" % self.checkout])

    def test_a_killed_installs_lock_frees_when_its_build_exits_though_git_leaves_processes_behind(self):
        real = [os.environ.get("GIT_CONFIG_GLOBAL") or os.path.expanduser("~/.gitconfig"),
                os.path.expanduser("~/.config/git/config")]
        hooks = self.tmp / "hooks"
        hooks.mkdir()
        (hooks / "post-checkout").write_text('#!/bin/sh\nsleep 60 >/dev/null 2>&1 &\necho $! >> "%s"\n'
                                             % (self.tmp / "hook-pids"))
        (hooks / "post-checkout").chmod(0o755)
        self.addCleanup(subprocess.run, ["sh", "-c", 'kill -9 $(cat "$0") 2>/dev/null', str(self.tmp / "hook-pids")])
        (self.tmp / "gitconfig").write_text("[include]\n%s[core]\n\tfsmonitor = true\n\thooksPath = %s\n"
                                            % ("".join("\tpath = %s\n" % path for path in real), hooks))
        (self.tmp / "bin" / "bash").symlink_to("/bin/bash")
        lock = self.cache / (self.a + ".lock")
        if shutil.which("lsof"):
            self.addCleanup(subprocess.run, ["sh", "-c", 'lsof -t "$0" | xargs kill -9', str(lock)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        install = self.install_held_in_its_build(self.a)
        self.addCleanup(install.communicate)
        self.assertTrue((self.tmp / "building").exists(), "the install never reached its build")
        os.kill(install.pid, signal.SIGKILL)
        (self.tmp / "release").touch()
        install.wait()
        after = subprocess.Popen([str(self.verify_path), "install", self.a], cwd=str(self.checkout),
                                 env=self.environment({}), start_new_session=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        try:
            out, _ = after.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(after.pid, signal.SIGKILL)
            after.communicate()
            self.fail("the next install still waits on the lock 20 s after the killed install's build exited")
        self.assertEqual((after.returncode, out), (0, self.cached_build(b"v1\n", self.a) + "\n"))

    def test_the_next_install_of_a_killed_builds_commit_builds_in_its_scratch(self):
        self.killed_build(self.a)
        kept = self.cache / (self.a + ".build") / "src" / "kept"
        kept.touch()
        install = self.install_held_in_its_build(self.a)
        self.assertTrue(kept.exists(), "the killed build's worktree and DerivedData are built on, not recreated")
        (self.tmp / "release").touch()
        out, _ = install.communicate(timeout=30)
        self.assertEqual((install.returncode, out), (0, self.cached_build(b"v1\n", self.a) + "\n"))
        self.assertEqual(self.entries(), [self.a, self.a + ".lock", "logs"])

    def test_a_commit_the_repo_does_not_know_is_refused_before_any_simulator(self):
        self.assertEqual(self.verify("install", "0badc0de"),
                         (2, "", "0badc0de names no single commit in this repo (unknown or ambiguous)\n"))
        self.assertEqual(self.calls(), [])


class EvidenceBase(Lane):
    def setUp(self):
        super().setUp()
        self.verify("build")

    def test_a_branchs_runs_land_in_the_main_checkout_under_the_branch_name(self):
        self.git("checkout", "-q", "-b", "lane/x+y")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"),
                         (0, self.launched(self.worktree_build(b"v2\n", self.b), lane="lane-x-y"), ""))

    def test_a_detached_worktrees_runs_land_under_its_directory_name(self):
        self.git("checkout", "-q", "--detach")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"),
                         (0, self.launched(self.worktree_build(b"v2\n", self.b), lane="detached-checkout"), ""))

    def test_verify_evidence_names_the_parent_of_the_run_directories(self):
        elsewhere = self.tmp / "elsewhere"
        code, out, err = self.verify("launch", "session", VERIFY_RUN="lane-1", VERIFY_EVIDENCE=str(elsewhere))
        self.assertEqual((code, out.splitlines()[-1], err), (0, "evidence %s/lane-1" % elsewhere, ""))

    def test_a_linked_worktrees_runs_land_in_the_main_checkout_so_they_outlive_it(self):
        linked = self.tmp / "linked"
        self.git("worktree", "add", "-q", "-b", "lane/linked", str(linked))
        verify = self.link_verify(linked)
        self.assertEqual(self.verify("diff", "01-before", "02-after-log", verify=verify, VERIFY_RUN="lane-1"), (1, "", (
            "no evidence directory for this run in %s; name one: VERIFY_RUN=<run> %s diff ...\nrecent runs:\n"
        ) % (self.checkout / ".claude" / "work" / "evidence" / "lane-linked", verify)))


class DriveGuard(Lane):
    def test_a_drive_command_refuses_another_live_runs_app(self):
        app = self.own_the_app("owner-1")
        for argv in [["tap", "-x", "5", "-y", "6"], ["hold", "weight-pill"], ["type", "245"], ["swipe", "up"],
                     ["shot", "01-before"], ["burst", "log-transition"], ["axe", "key", "40"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="lane-1"), (75, "", (
                    "the app on {sim} belongs to run owner-1 (pid {pid}), not to lane-1, so this would drive another "
                    "run's app; launch yours first: SIM={sim} VERIFY_RUN=lane-1 {verify} launch <fixture>\n"
                ).format(sim=self.sim, pid=app.pid, verify=self.verify_path)))
                self.assertEqual(self.calls(), [], "nothing was driven or filmed")

    def test_a_refused_relaunch_of_the_same_run_drives_nothing_until_a_launch_of_it_succeeds(self):
        self.verify("build")
        self.verify("install", self.a)
        control = self.own_the_app("ui12")
        refusal = ("%s holds %s, and this launch would replace it with %s. To run the cached build: launch --at %s "
                   "session. To replace it: install, then launch.") % (
            self.sim, self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b), self.a[:8])
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 65)
        for argv in [["tap", "-x", "5", "-y", "6"], ["shot", "02-head"], ["type", "245"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="ui12"), (75, "", (
                    "the last launch of run ui12 on {sim} was refused, so this would drive whatever that refusal left "
                    "running ({refusal}); stop it, then launch again: SIM={sim} VERIFY_RUN=ui12 {verify} stop, then "
                    "SIM={sim} VERIFY_RUN=ui12 {verify} launch <fixture>\n"
                ).format(sim=self.sim, refusal=refusal, verify=self.verify_path)))
                self.assertEqual(self.calls(), [], "the control app is neither driven nor filmed as the head")
        self.assertRegex((self.evidence("main", "ui12") / "launches.txt").read_text(),
                         r"^\S+ launch refused: %s\n$" % re.escape(refusal))
        control.kill()
        control.wait()
        self.assertEqual(self.verify("install")[0], 0)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="ui12")[0], 75, "an install is not a launch")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 0)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="ui12"), (0, "", ""))

    def test_a_drive_that_names_no_run_is_refused_after_the_refused_relaunch_of_the_run_it_would_drive(self):
        self.verify("build")
        self.verify("install", self.a)
        self.own_the_app("ui12")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 65)
        for argv in [["shot", "02-head"], ["tap", "-x", "5", "-y", "6"]]:
            with self.subTest(argv=argv):
                code, out, err = self.verify(*argv)
                self.assertEqual((code, out), (75, ""))
                self.assertRegex(err, r"^the last launch of run ui12 on %s was refused" % self.sim)
                self.assertEqual(self.calls(), [], "the stale app is neither driven nor filmed into ui12's evidence")

    def test_a_cache_build_that_fails_refuses_the_run_until_a_launch_of_it_succeeds(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        refusal = "app on %s unchanged: %s; this launch wanted %s from the app cache, and its build failed" % (
            self.sim, self.worktree_build(b"v2\n", self.b), self.a[:8])
        code, out, err = self.verify("launch", "--at", self.a, "session", VERIFY_RUN="r1", STUB_BUILD_FAIL="1")
        self.assertEqual((code, out, err.splitlines()[-1]), (65, "", refusal))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="r1")[0], 75)
        self.assertRegex((self.evidence("main", "r1") / "launches.txt").read_text(),
                         r"\n\S+ launch refused: %s\n$" % re.escape(refusal))

    def test_a_cache_build_that_never_gets_a_build_slot_refuses_the_run_until_a_launch_of_it_succeeds(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        refusal = "app on %s unchanged: %s; this launch wanted %s from the app cache" % (
            self.sim, self.worktree_build(b"v2\n", self.b), self.a[:8])
        code, out, err = self.verify("launch", "--at", self.a, "session", VERIFY_RUN="r1", WORKOUT_LOAD_LIMIT="50")
        self.assertEqual((code, out, err.splitlines()[-1]), (75, "", refusal))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="r1")[0], 75)

    def test_a_drive_that_names_no_run_is_refused_after_a_launch_that_named_none_was_refused(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session")[0], 0)
        run = (Path("/tmp/workout-verify-%s" % self.sim) / "run").read_text().strip()
        refusal = "app on %s unchanged: %s; this launch wanted %s from the app cache, and its build failed" % (
            self.sim, self.worktree_build(b"v2\n", self.b), self.a[:8])
        self.assertEqual(self.verify("launch", "--at", self.a, "session", STUB_BUILD_FAIL="1")[0], 65)
        for argv in [["tap", "-x", "5", "-y", "6"], ["shot", "02-head"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv), (75, "", (
                    "the last launch of run {run} on {sim} was refused, so this would drive whatever that refusal "
                    "left running ({refusal}); stop it, then launch again: SIM={sim} {verify} stop, then "
                    "SIM={sim} {verify} launch <fixture>\n"
                ).format(run=run, sim=self.sim, refusal=refusal, verify=self.verify_path)))
                self.assertEqual(self.calls(), [], "the app the refusal left is neither driven nor filmed")
        self.assertRegex((self.evidence("main", run) / "launches.txt").read_text(),
                         r"\n\S+ launch refused: %s\n$" % re.escape(refusal))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r2")[0], 0)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""), "any launch that succeeds clears it")

    def test_a_drive_that_names_no_run_is_refused_after_the_first_launch_on_the_simulator_was_refused(self):
        self.assertEqual(self.verify("launch", "session")[0], 65)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6")[0], 75)
        self.assertEqual(self.calls(), [])

    def test_a_refused_launch_that_named_no_run_does_not_stop_a_named_owner_driving_unnamed(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session")[0], 0)
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="owner-1")[0], 0)
        self.assertEqual(self.verify("launch", "--at", self.a, "session", STUB_BUILD_FAIL="1")[0], 65)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="owner-1"), (0, "", ""))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))

    def test_a_named_launch_that_starts_but_never_comes_up_is_not_held_to_an_earlier_unnamed_refusal(self):
        self.assertEqual(self.verify("launch", "session")[0], 65)
        self.verify("build")
        (self.tmp / "describe-ui.json").write_text(MINI.replace('"pid": 4121', '"pid": 99999999'))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="owner-1")[0], 70)
        (self.tmp / "describe-ui.json").write_text(MINI)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))

    def test_a_refused_install_blocks_no_drive(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        self.assertEqual(self.verify("install", self.a, VERIFY_RUN="r1", STUB_BUILD_FAIL="1")[0], 65)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="r1"), (0, "", ""))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))

    def test_a_run_refused_because_another_runs_app_is_alive_is_not_told_to_stop_it(self):
        self.verify("build")
        app = self.own_the_app("owner-1")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 75)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="lane-1"), (75, "", (
            "the app on {sim} belongs to run owner-1 (pid {pid}), not to lane-1, so this would drive another "
            "run's app; launch yours first: SIM={sim} VERIFY_RUN=lane-1 {verify} launch <fixture>\n"
        ).format(sim=self.sim, pid=app.pid, verify=self.verify_path)))

    def test_another_runs_refused_launch_does_not_stop_the_owner(self):
        self.verify("build")
        self.own_the_app("owner-1")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 75)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="owner-1"), (0, "", ""))

    def test_the_owner_an_unnamed_caller_and_a_dead_owner_still_drive(self):
        self.own_the_app("owner-1")
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="owner-1"), (0, "", ""))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))
        (Path("/tmp/workout-verify-%s" % self.sim) / "pid").write_text("99999999\n")
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="lane-1"), (0, "", ""))
        self.assertEqual(self.calls(), ["axe tap --udid %s --wait-timeout 3 -x 5 -y 6" % self.sim])


class KeyboardReset(Lane):
    RESET = "xcrun simctl spawn %s defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false"
    READ = "xcrun simctl spawn %s defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled"

    def minimized(self, value):
        (self.tmp / "minimization").write_text(value)

    def test_launch_resets_a_minimized_keyboard_before_it_starts_the_app_and_says_so(self):
        self.verify("build")
        self.minimized("1\n")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (
            0, self.launched(self.worktree_build(b"v2\n", self.b)),
            "AutomaticMinimizationEnabled was 1 on %s, which hides the software keyboard (issue 700); "
            "this launch reset it to 0\n" % self.sim))
        calls = self.calls()
        start = [index for index, call in enumerate(calls) if call.startswith("xcrun simctl launch")][0]
        self.assertEqual(calls[start - 2:start], [self.READ % self.sim, self.RESET % self.sim])
        self.assertEqual((self.tmp / "minimization").read_text(), "0\n")

    def test_launch_leaves_a_keyboard_preference_that_is_0_or_unset_alone(self):
        self.verify("build")
        for value in [None, "0\n"]:
            with self.subTest(value=value):
                if value:
                    self.minimized(value)
                code, _, err = self.verify("launch", "session", VERIFY_RUN="lane-1")
                self.assertEqual((code, err), (0, ""))
                self.assertIn(self.READ % self.sim, self.calls())
                self.assertNotIn(self.RESET % self.sim, self.calls())

    def test_doctor_fails_a_minimized_keyboard_and_passes_one_that_is_not(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        self.minimized("1\n")
        code, out, _ = self.verify("doctor")
        self.assertEqual((code, out.splitlines()[-1]), (1, (
            "FAIL AutomaticMinimizationEnabled is 1 on {sim}, so a focused field shows no software keyboard "
            "(issue 700); the next launch resets it (run: {verify} launch <fixture>)").format(
                sim=self.sim, verify=self.verify_path)))
        self.minimized("0\n")
        self.assertEqual(self.verify("doctor")[1].splitlines()[-1],
                         "ok   AutomaticMinimizationEnabled is not 1 on %s" % self.sim)

    def test_type_resets_the_keyboard_preference_after_axe_and_keeps_axes_status(self):
        self.assertEqual(self.verify("type", "245", STUB_AXE_EXIT="3"), (3, "", KEYBOARD))
        self.assertEqual(self.calls(), ["axe type --udid %s --stdin" % self.sim, self.RESET % self.sim])

    def test_an_axe_keyboard_verb_resets_it_too_and_any_other_verb_does_not(self):
        for verb in [["key", "42"], ["key-sequence", "--keycodes", "42,42"], ["key-combo", "--modifiers", "227", "--key", "4"],
                     ["type", "245"]]:
            with self.subTest(verb=verb[0]):
                self.assertEqual(self.verify("axe", *verb), (0, "", KEYBOARD))
                self.assertEqual(self.calls(), ["axe %s --udid %s" % (" ".join(verb), self.sim), self.RESET % self.sim])
        self.assertEqual(self.verify("axe", "tap", "-x", "5", "-y", "6", STUB_AXE_EXIT="4"), (4, "", ""))
        self.assertEqual(self.calls(), ["axe tap -x 5 -y 6 --udid %s" % self.sim])


AXE_STUB = """#!/bin/sh
case $1 in
  screenshot) cp "$STUB_FRAME" "$5" ;;
  describe-ui) cat "$STUB_TREE" ;;
  *) exit 1 ;;
esac
"""
AFTER_LOG = MINI.replace("Weight, 237.5", "Weight, 252.5")


class VerifyShot(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        skill = self.root / ".agents" / "skills" / "verify"
        skill.mkdir(parents=True)
        (self.root / "scripts").mkdir()
        (skill / "verify.sh").symlink_to(SKILL / "verify.sh")
        (skill / "tree.py").symlink_to(SKILL / "tree.py")
        (self.root / "scripts" / "sim-lock.sh").symlink_to(REPO / "scripts" / "sim-lock.sh")
        axe = self.root / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        axe.write_text(AXE_STUB)
        axe.chmod(0o755)
        self.verify = skill / "verify.sh"
        self.sim = "SHOT-TEST-%d" % os.getpid()
        self.evidence = self.root / "evidence" / "issue-674"
        self.home, self.stage = self.root / "home.png", self.root / "stage.png"
        write_png(self.home, 4, 4, (32, 96, 160))
        write_png(self.stage, 4, 4, (240, 240, 240))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def shot(self, name, frame, tree):
        described = self.root / ("%s.describe-ui.json" % name)
        described.write_text(tree)
        env = dict(os.environ, SIM=self.sim, VERIFY_RUN="issue-674", STUB_FRAME=str(frame), STUB_TREE=str(described),
                   VERIFY_EVIDENCE=str(self.evidence.parent))
        done = subprocess.run(
            [str(self.verify), "shot", name], cwd=str(self.root), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        return done.returncode, done.stdout, done.stderr

    def test_a_frame_identical_to_the_last_shot_while_the_tree_moved_is_refused(self):
        self.assertEqual(self.shot("01-before", self.stage, MINI)[0], 0)
        code, out, err = self.shot("02-after-log", self.stage, AFTER_LOG)
        self.assertEqual((code, out), (70, ""), "a wedged simulator returned the old frame: %s" % err)
        self.assertEqual(err, (
            "refused 02-after-log: its frame is byte-identical to 01-before.png but its tree changed, "
            "so the pixels did not move while the tree did\n"
            "changed from 01-before to 02-after-log, frames ignored:\n"
            "- AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n"
            "+ AXButton\tweight-pill\tWeight, 252.5\t\t@98,531 206x66\n"
            "\n"
            "2 changed, 3 unchanged\n"
            "if those lines are text the app does not draw, 01-before.png already shows this screen and the "
            "lines are the evidence\n"
            "if not, the shot fired before a transition drew (wait a second and shoot again) or the screenshot "
            "pipeline is wedged, as the axe button lock in issue 674 left it, and 01-before.png may be frozen too "
            "(run: xcrun simctl shutdown %s, then SIM=%s VERIFY_RUN=issue-674 %s launch <fixture>, "
            "and shoot 01-before again)\n" % (self.sim, self.sim, self.verify)
        ))
        self.assertEqual(sorted(p.name for p in self.evidence.iterdir() if not p.name.startswith(".")),
                         ["01-before.png", "01-before.tree.txt"], "the frozen frame is not filed as evidence")
        code, out, err = self.shot("02-after-log", self.home, AFTER_LOG)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[-1], "2 changed, 3 unchanged", "shooting again once the frame moved lands")

    def test_retaking_a_landed_shot_with_its_own_frame_while_the_tree_moved_is_refused(self):
        self.assertEqual(self.shot("01-before", self.home, MINI)[0], 0)
        self.assertEqual(self.shot("02-after-log", self.stage, AFTER_LOG)[0], 0)
        code, out, err = self.shot("02-after-log", self.stage, AFTER_LOG.replace("1:58", "1:57"))
        self.assertEqual((code, out), (70, ""), err)
        self.assertEqual(err.splitlines()[0], "refused 02-after-log: its frame is byte-identical to 02-after-log.png "
                         "but its tree changed, so the pixels did not move while the tree did")
        self.assertEqual((self.evidence / "02-after-log.png").read_bytes(), self.stage.read_bytes())
        self.assertIn("AXStaticText\t\tRest 1:58 remaining\t\t@100,816 202x51",
                      (self.evidence / "02-after-log.tree.txt").read_text().splitlines(),
                      "the shot that landed under that name keeps its tree")

    def test_an_unchanged_screen_with_an_unchanged_tree_still_shoots(self):
        self.assertEqual(self.shot("01-before", self.stage, MINI)[0], 0)
        code, out, err = self.shot("02-still", self.stage, MINI)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, "%s/02-still.png\n%s/02-still.tree.txt\nno tree changes from 01-before to 02-still, frames ignored\n"
                         % (self.evidence, self.evidence), "the same bytes are the right frame when nothing changed")


@unittest.skipUnless(sys.platform == "darwin", "the tiler is a Swift script and runs on macOS only")
class VerifySheet(unittest.TestCase):
    def setUp(self):
        self.run = "sheettest-%d" % os.getpid()
        self.evidence = Path(tempfile.mkdtemp())
        self.dir = self.evidence / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        for captured, name in enumerate(["02-b", "01-a", "03-c"]):
            write_png(self.dir / ("%s.png" % name), 120, 260, (32, 96, 160))
            tree = self.dir / ("%s.tree.txt" % name)
            tree.write_text("AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n")
            os.utime(tree, (captured + 1, captured + 1))

    def tearDown(self):
        shutil.rmtree(self.evidence, ignore_errors=True)

    def test_the_sheet_numbers_every_shot_of_the_run_in_capture_order(self):
        code, out, err = verify_sh("sheet", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(len(out.splitlines()), 1, "three shots are one page")
        fields = out.rstrip("\n").split("\t")
        self.assertEqual(len(fields), 5, out)
        self.assertEqual(fields[0], str(self.dir / "_sheet.png"), "one sheet per run, beside the shots")
        self.assertEqual(fields[2], "3 images")
        self.assertEqual(fields[4], "1. 02-b  2. 01-a  3. 03-c", "capture order, not name order")

    def test_a_second_sheet_of_the_same_shots_is_the_same_bytes(self):
        self.assertEqual(verify_sh("sheet", run=self.run, evidence=self.evidence)[0], 0)
        first = (self.dir / "_sheet.png").read_bytes()
        self.assertEqual(verify_sh("sheet", run=self.run, evidence=self.evidence)[0], 0)
        self.assertEqual((self.dir / "_sheet.png").read_bytes(), first, "rerunning converges")

    def test_a_run_with_no_shots_says_how_to_take_one(self):
        empty = self.dir.with_name("%s-empty" % self.run)
        empty.mkdir(parents=True, exist_ok=True)
        code, out, err = verify_sh("sheet", run=empty.name, evidence=self.evidence)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("shot NAME", err, "the way out of an empty run")


@unittest.skipUnless(sys.platform == "darwin", "crop cuts with the Swift tiler and reads colours with sips, both macOS only")
class VerifyCrop(unittest.TestCase):
    SURROUND, PILL = (240, 240, 240), (32, 96, 160)

    def setUp(self):
        self.run = "croptest-%d" % os.getpid()
        self.evidence = Path(tempfile.mkdtemp())
        self.dir = self.evidence / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(BEFORE_TREE, self.dir / "01-before.tree.txt")
        write_png(self.dir / "01-before.png", 804, 1748, self.SURROUND, box_frame=(196, 1062, 412, 132), box_colour=self.PILL)
        self.crop = self.dir / "01-before-crop-90_523_222x82.png"

    def tearDown(self):
        shutil.rmtree(self.evidence, ignore_errors=True)

    def colours(self, png, points):
        probe = Path(tempfile.mkdtemp())
        try:
            bmp = probe / "probe.bmp"
            subprocess.run(["sips", "-s", "format", "bmp", str(png), "--out", str(bmp)],
                           stdout=subprocess.DEVNULL, check=True)
            data = bmp.read_bytes()
        finally:
            shutil.rmtree(probe, ignore_errors=True)
        offset, = struct.unpack_from("<I", data, 10)
        width, height = struct.unpack_from("<ii", data, 18)
        depth, = struct.unpack_from("<H", data, 28)
        stride = (width * depth // 8 + 3) // 4 * 4
        found = []
        for x, y in points:
            row = y if height < 0 else height - 1 - y
            at = offset + row * stride + x * depth // 8
            found.append(tuple(data[at:at + 3][::-1]))
        return found

    def test_a_crop_by_id_is_the_shots_own_pixels_around_the_element(self):
        self.assertEqual(verify_sh("crop", "01-before", "weight-pill", run=self.run, evidence=self.evidence),
                         (0, "%s\t444x164\n" % self.crop, ""), "8 points around the pill at 2 pixels a point")
        surround, pill = self.SURROUND, self.PILL
        self.assertEqual(self.colours(self.crop, [(15, 16), (16, 15), (16, 16), (427, 147), (428, 147), (427, 148)]),
                         [surround, surround, pill, pill, surround, surround],
                         "the pill starts 16 pixels in from the top left and ends 16 from the bottom right")

    def test_a_crop_at_the_top_left_corner_starts_there(self):
        write_png(self.dir / "01-before.png", 804, 1748, self.SURROUND, box_frame=(0, 0, 8, 8), box_colour=self.PILL)
        corner = self.dir / "01-before-crop-0_0_10x10.png"
        self.assertEqual(verify_sh("crop", "01-before", "0", "0", "10", "10", run=self.run, evidence=self.evidence),
                         (0, "%s\t20x20\n" % corner, ""))
        self.assertEqual(self.colours(corner, [(0, 0), (7, 7), (8, 8)]), [self.PILL, self.PILL, self.SURROUND],
                         "sips centres a crop whose offset is 0 0, which would show the surround alone")

    def test_a_crop_is_not_a_shot(self):
        self.assertEqual(verify_sh("crop", "01-before", "weight-pill", run=self.run, evidence=self.evidence)[0], 0)
        code, out, err = verify_sh("sheet", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.split("\t")[4], "1. 01-before\n", "the sheet tiles the shot alone")
        self.assertEqual(verify_sh("diff", "01-before", self.crop.stem, run=self.run, evidence=self.evidence), (
            1, "", "no shot %s in %s; shots: 01-before \n" % (self.crop.stem, self.dir)))
        code, out, err = verify_sh("shot", self.crop.stem, run=self.run, evidence=self.evidence)
        self.assertEqual((code, out), (2, ""), "the underscore makes a crop's name illegal for a shot: %s" % err)

    def test_the_same_region_by_points_converges_on_one_file(self):
        self.assertEqual(verify_sh("crop", "01-before", "weight-pill", run=self.run, evidence=self.evidence)[0], 0)
        first = self.crop.read_bytes()
        self.assertEqual(verify_sh("crop", "01-before", "90", "523", "222", "82", run=self.run, evidence=self.evidence),
                         (0, "%s\t444x164\n" % self.crop, ""))
        self.assertEqual(sorted(p.name for p in self.dir.iterdir() if "-crop-" in p.name), [self.crop.name])
        self.assertEqual(self.crop.read_bytes(), first, "rerunning converges")

    def test_a_missing_shot_lists_the_runs_shots(self):
        self.assertEqual(verify_sh("crop", "09-nope", "0", "0", "10", "10", run=self.run, evidence=self.evidence),
                         (1, "", "no shot 09-nope in %s; shots: 01-before \n" % self.dir))
        (self.dir / "02-half.png").write_bytes(b"png")
        self.assertEqual(verify_sh("crop", "02-half", "weight-pill", run=self.run, evidence=self.evidence)[0], 1,
                         "a PNG whose tree never landed is not a shot")


class BurstFrames(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        second = 1000000000
        for name, at in [("f00.png", 999.900), (".drive-returned", 1000.000),
                         ("f01.png", 1000.142), ("f02.png", 1000.373)]:
            (self.dir / name).write_bytes(b"png")
            os.utime(self.dir / name, ns=(int(at * second), int(at * second)))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_frames_are_named_by_when_they_were_captured(self):
        done = subprocess.run(
            [sys.executable, str(SKILL / "frames.py"), str(self.dir)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(
            [Path(line).name for line in done.stdout.splitlines()],
            ["before.png", "+0142ms.png", "+0373ms.png"],
            "capture order, timed from the drive command's return",
        )
        self.assertEqual(
            sorted(path.name for path in self.dir.glob("*.png")),
            ["+0142ms.png", "+0373ms.png", "before.png"],
            "renamed on disk, because the tiler labels a cell with its file stem",
        )

    def test_two_frames_in_one_millisecond_stop_the_burst_and_lose_nothing(self):
        second = 1000000000
        (self.dir / "f03.png").write_bytes(b"a second frame")
        os.utime(self.dir / "f03.png", ns=(int(1000.373 * second), int(1000.373 * second)))
        done = subprocess.run(
            [sys.executable, str(SKILL / "frames.py"), str(self.dir)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.assertNotEqual(done.returncode, 0, "one cell must never stand for two moments")
        self.assertIn("+0373ms.png", done.stderr)
        self.assertEqual(len(list(self.dir.glob("*.png"))), 4, "no frame was overwritten")


TAKE_LINES = """format=take/1
name=appear
video=appear.mp4
drive=launch --animated session
tail=2.0
load_limit=50
load_before=12.31
load_after=14.02
started=1791817306.217
drive_start=0.004
drive_end=2.694
stopped=4.714
recorder_exit=0
recorder_early=0
frames=37
first_frame=0.000
last_frame=3.402
video_px=1206x2622
verdict=VALID
invalid=
invalid_rules=
"""
STAMP = TAKE_LINES + ("screen_pt=402x874\ncard_pt=@16,476 370x308\nanimations=on\n"
                      "app=app 804e750cad00 commit ea5af074 (this worktree's build)\n")


def stamp_with(**changes):
    text = STAMP
    for key, value in changes.items():
        text = re.sub(r"(?m)^%s=.*$" % key, "%s=%s" % (key, value), text)
    return take.parse(text)


class TakeJudge(unittest.TestCase):
    def test_a_take_that_breaks_no_rule_is_valid_and_writes_back_the_same_take_lines(self):
        self.assertEqual(take.judge(take.parse(STAMP)), [])
        self.assertEqual("\n".join(take.take_lines(take.parse(STAMP))) + "\n", TAKE_LINES)

    def test_the_summary_reads_the_whole_stamp(self):
        self.assertEqual(take.summary(take.parse(STAMP)), (
            "take appear VALID 4.71 s, drive +0.00..+2.69 s, 37 frames, last +3.40 s, load 12.3 then 14.0 (limit 50), "
            "animations on"))
        self.assertEqual(take.summary(stamp_with(drive="", frames=1, load_after="63.20", animations="off")), (
            "take appear INVALID 4.71 s, no drive, 1 frame, last +3.40 s, load 12.3 then 63.2 (limit 50), "
            "animations off"))

    def test_parse_reads_the_four_lines_verify_sh_appends_and_defaults_them_when_absent(self):
        appended = take.parse(STAMP)
        self.assertEqual((appended.screen_pt, appended.card_pt, appended.animations, appended.app),
                         ((402, 874), (16, 476, 370, 308), "on",
                          "app 804e750cad00 commit ea5af074 (this worktree's build)"))
        bare = take.parse(TAKE_LINES)
        self.assertEqual((bare.screen_pt, bare.card_pt, bare.animations, bare.app), (None, None, "unknown", ""))

    def test_card_pt_is_the_trees_frame_of_the_card_in_points_or_none(self):
        card = take.parse(STAMP).card_pt
        self.assertEqual((type(card), card, card.center, card.text),
                         (tree.Frame, (16, 476, 370, 308), (201.0, 630.0), "@16,476 370x308"))
        self.assertEqual(take.parse(STAMP.replace("card_pt=@16,476 370x308", "card_pt=@-83,476 4770x308")).card_pt.text,
                         "@-83,476 4770x308")
        self.assertEqual(take.parse(STAMP.replace("card_pt=@16,476 370x308", "card_pt=none")).card_pt, "none")

    def test_parse_refuses_a_stamp_that_is_not_take_1_naming_what_is_wrong(self):
        for text, why in [
            (STAMP.replace("format=take/1", "format=take/2"), "format=take/2, not take/1"),
            (STAMP.replace("format=take/1\n", ""), "no format=take/1"),
            (re.sub(r"(?m)^(drive_start|frames)=.*\n", "", STAMP), "no drive_start= frames="),
            (STAMP.replace("frames=37", "frames=many"), "frames=many does not parse"),
            (STAMP.replace("screen_pt=402x874", "screen_pt=402"), "screen_pt=402 does not parse"),
            (STAMP.replace("card_pt=@16,476 370x308", "card_pt=@16,476"), "card_pt=@16,476 does not parse"),
        ]:
            with self.subTest(why=why):
                with self.assertRaises(ValueError) as raised:
                    take.parse(text)
                self.assertEqual(str(raised.exception), why)

    def test_load_at_or_over_the_limit_at_the_end(self):
        self.assertEqual(take.judge(stamp_with(load_after="63.20")), [("load", "load 63.2 at the end, at or over 50")])
        self.assertEqual(take.judge(stamp_with(load_after="50.00")), [("load", "load 50.0 at the end, at or over 50")])
        self.assertEqual(take.judge(stamp_with(load_after="49.99")), [])

    def test_load_over_the_limit_at_the_start_is_record_s_refusal_not_a_rule_so_the_take_is_valid(self):
        self.assertEqual(take.judge(stamp_with(load_before="63.20", load_after="14.02")), [])

    def test_a_recorder_that_stopped_early_or_exited_nonzero(self):
        self.assertEqual(take.judge(stamp_with(recorder_early="1")),
                         [("recorder_early", "the recorder stopped before the take ended")])
        self.assertEqual(take.judge(stamp_with(recorder_exit="1")),
                         [("recorder_exit", "recorder exit 1 after SIGINT; the video may be cut short")])

    def test_a_drive_needs_a_frame_after_the_first_at_or_after_it_began(self):
        self.assertEqual(take.judge(stamp_with(drive_start="0.320", last_frame="0.300")), [("coverage",
            "the screen never changed after the drive began at +0.32 s, so the take shows nothing the drive did")])
        self.assertEqual(take.judge(stamp_with(drive_start="0.000", first_frame="0.000", last_frame="0.000",
                                               frames="1")), [("coverage",
            "the screen never changed after the drive began at +0.00 s, so the take shows nothing the drive did")])
        self.assertEqual(take.judge(stamp_with(drive_start="0.320", last_frame="0.320", frames="2")), [])

    def test_a_take_with_no_drive_needs_two_frames(self):
        self.assertEqual(take.judge(stamp_with(drive="", frames="1", last_frame="0.000")),
                         [("coverage", "one frame: the screen never changed while recording")])
        self.assertEqual(take.judge(stamp_with(drive="", frames="2")), [])

    def test_every_failed_rule_gives_its_rule_and_reason_in_rule_order_and_the_stamp_lists_the_rules(self):
        broken = stamp_with(load_after="70.00", recorder_early="1", recorder_exit="2", drive_start="3.500")
        self.assertEqual(take.judge(broken), [
            ("load", "load 70.0 at the end, at or over 50"),
            ("recorder_early", "the recorder stopped before the take ended"),
            ("recorder_exit", "recorder exit 2 after SIGINT; the video may be cut short"),
            ("coverage",
             "the screen never changed after the drive began at +3.50 s, so the take shows nothing the drive did"),
        ])
        self.assertEqual(take.take_lines(broken)[-3:], [
            "verdict=INVALID",
            "invalid=load 70.0 at the end, at or over 50; the recorder stopped before the take ended; recorder exit "
            "2 after SIGINT; the video may be cut short; the screen never changed after the drive began at +3.50 s, "
            "so the take shows nothing the drive did",
            "invalid_rules=load,recorder_early,recorder_exit,coverage",
        ])



RECORDER_STUB = """#!/bin/sh
echo $$ > "{dir}/recorder.pid"
if [ -n "${STUB_STUCK:-}" ]; then trap '' INT; else trap 'echo mp4 > "$8"; exit 0' INT; fi
[ -n "${STUB_NEVER_STARTS:-}" ] || echo "Recording started" >&2
while :; do sleep 0.1; done
"""
WRAPPED_LAUNCH_STUB = """#!/bin/bash
trap 'echo "the EXIT trap ran" > "{dir}/drive-exit"' EXIT
[ "$1" != fail ] || exit 4
touch "{dir}/driving"
while :; do sleep 0.1; done
"""


class Film(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        (self.tmp / "bin").mkdir()
        for path, stub in [(self.tmp / "bin" / "xcrun", RECORDER_STUB), (self.tmp / "verify.sh", WRAPPED_LAUNCH_STUB)]:
            path.write_text(stub.replace("{dir}", str(self.tmp)))
            path.chmod(0o755)
        self.env = dict(os.environ, PATH="%s:%s" % (self.tmp / "bin", os.environ["PATH"]))
        self.addCleanup(self.kill_recorder)
        self.saved = take.STOP_GRACE
        self.addCleanup(setattr, take, "STOP_GRACE", self.saved)
        take.STOP_GRACE = 0.3

    def kill_recorder(self):
        pid = self.tmp / "recorder.pid"
        if pid.exists():
            try:
                os.kill(int(pid.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass

    def film(self, drive, start_timeout=5.0, **env):
        with mock.patch.dict(os.environ, dict(self.env, **env)), tempfile.TemporaryFile("w+") as stderr, \
                contextlib.redirect_stderr(stderr):
            try:
                take.film("SIM", "lane-1", str(self.tmp / "verify.sh"), self.tmp / "appear.mp4", 0.0, 50.0, 1.0,
                          drive, start_timeout)
            except (take.DriveFailed, take.NoTake) as failure:
                stderr.seek(0)
                return type(failure).__name__, str(failure), stderr.read()
        self.fail("film returned a take")

    def stuck(self):
        pid = int((self.tmp / "recorder.pid").read_text())
        return "simctl recordVideo (pid %d) is still running 0.3 s after SIGINT; stop it with: kill -INT %d\n" % (pid, pid)

    def test_a_failed_drive_is_the_failure_even_when_the_recorder_will_not_stop(self):
        failure = self.film(["fail"], STUB_STUCK="1")
        self.assertEqual(failure, ("DriveFailed", "the drive `fail` exited 4, so the take is not kept", self.stuck()))

    def test_a_recorder_that_never_started_is_the_failure_even_when_it_will_not_stop(self):
        failure = self.film(["fail"], start_timeout=0.3, STUB_STUCK="1", STUB_NEVER_STARTS="1")
        self.assertEqual(failure, ("NoTake", "simctl recordVideo did not start capturing within 0.3 s, so nothing "
                                             "was driven", self.stuck()))

    def test_an_interrupted_take_gives_the_drive_sigint_so_its_exit_trap_runs(self):
        record = subprocess.Popen(
            [sys.executable, str(SKILL / "take.py"), "record", "--sim", "SIM", "--run", "lane-1", "--verify",
             str(self.tmp / "verify.sh"), "--out", str(self.tmp / "appear.mp4"), "--tail", "0", "--limit", "50",
             "--load-before", "1", "--", "launch", "--animated", "session"],
            env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.addCleanup(record.kill)
        deadline = time.time() + 10
        while not (self.tmp / "driving").exists():
            self.assertLess(time.time(), deadline, "the drive never started")
            time.sleep(0.05)
        record.send_signal(signal.SIGINT)
        self.assertEqual(record.communicate(timeout=10), ("", ""))
        self.assertEqual(record.returncode, 130)
        self.assertEqual((self.tmp / "drive-exit").read_text(), "the EXIT trap ran\n")
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()),
                         ["bin", "drive-exit", "driving", "recorder.pid", "verify.sh"])


SYSCTL_STUB = """#!/bin/sh
if [ -f "{dir}/stopped" ]; then echo "{ ${STUB_LOAD_AFTER:-14.02} 9.00 8.00 }"; else echo "{ ${STUB_LOAD_BEFORE:-12.31} 9.00 8.00 }"; fi
"""
FFPROBE_STUB = """#!/bin/sh
for video; do :; done
[ -s "$video" ] || { echo "$video: No such file or directory" >&2; exit 1; }
frames=
for t in ${STUB_PTS:-0.000000 3.402000 0.400000}; do frames="$frames${frames:+, }{\\"pts_time\\": \\"$t\\"}"; done
echo "{\\"frames\\": [$frames], \\"streams\\": [{\\"width\\": 1206, \\"height\\": 2622}]}"
"""
CLAIMING_SYSCTL_STUB = """#!/bin/sh
if [ -f "{dir}/claimed" ]; then echo "{ 12.31 9.00 8.00 }"; exit 0; fi
touch "{dir}/claimed"
echo lane-2 > "{state}/run"
echo {pid} > "{state}/pid"
echo "{ 63.20 9.00 8.00 }"
"""
TAKE_KEYS = ["format", "name", "video", "drive", "tail", "load_limit", "load_before", "load_after", "started",
             "drive_start", "drive_end", "stopped", "recorder_exit", "recorder_early", "frames", "first_frame",
             "last_frame", "video_px", "verdict", "invalid", "invalid_rules", "screen_pt", "card_pt", "animations",
             "app"]
SUMMARY = re.compile(r"^take appear (VALID|INVALID) \d+\.\d\d s, drive \+\d+\.\d\d\.\.\+\d+\.\d\d s, 3 frames, "
                     r"last \+3\.40 s, load 12\.3 then (\d+\.\d) \(limit 50\), animations on$")


class Record(Lane):
    def setUp(self):
        super().setUp()
        for name, stub in [("sysctl", SYSCTL_STUB), ("ffprobe", FFPROBE_STUB)]:
            (self.tmp / "bin" / name).write_text(stub.replace("{dir}", str(self.tmp)))
            (self.tmp / "bin" / name).chmod(0o755)
        self.verify("build")
        self.run = self.evidence("main", "lane-1")

    def launch(self):
        self.assertEqual(self.verify("launch", "--animated", "session", VERIFY_RUN="lane-1")[0], 0)

    def record(self, *argv, **env):
        for marker in ["signals", "stopped"]:
            (self.tmp / marker).unlink(missing_ok=True)
        env.setdefault("VERIFY_RUN", "lane-1")
        return self.verify("record", "appear", "--tail", "0.5", *argv, **env)

    def stamp(self, run=None):
        return [line.split("=", 1) for line in ((run or self.run) / "appear.take").read_text().splitlines()]

    def signals(self):
        return (self.tmp / "signals").read_text()

    def listing(self, directory):
        return sorted(p.name for p in directory.iterdir())

    def test_a_valid_take_stamps_every_key_in_order_and_stops_the_recorder_with_one_sigint(self):
        self.launch()
        before = time.time()
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, err), (0, ""))
        paths, summary = out.splitlines()[:2], out.splitlines()[2:]
        self.assertEqual(paths, [str(self.run / "appear.mp4"), str(self.run / "appear.take")])
        self.assertEqual([SUMMARY.match(line).groups() for line in summary], [("VALID", "14.0")])
        stamp = self.stamp()
        self.assertEqual([key for key, _ in stamp], TAKE_KEYS)
        values = dict(stamp)
        timed = {key: float(values.pop(key)) for key in ["started", "drive_start", "drive_end", "stopped"]}
        self.assertEqual(values, {
            "format": "take/1", "name": "appear", "video": "appear.mp4", "drive": "tap -x 5 -y 6", "tail": "0.5",
            "load_limit": "50", "load_before": "12.31", "load_after": "14.02", "recorder_exit": "0",
            "recorder_early": "0", "frames": "3", "first_frame": "0.000", "last_frame": "3.402",
            "video_px": "1206x2622", "verdict": "VALID", "invalid": "", "invalid_rules": "", "screen_pt": "402x874",
            "card_pt": "@-83,476 4770x308", "animations": "on",
            "app": self.worktree_build(b"v2\n", self.b)})
        self.assertTrue(before < timed["started"] < time.time(), timed)
        self.assertTrue(0 <= timed["drive_start"] <= timed["drive_end"], timed)
        self.assertGreaterEqual(timed["stopped"] - timed["drive_end"], 0.5, "the tail ran after the drive")
        self.assertEqual(self.signals(), "INT\n")
        self.assertEqual((self.run / "appear.mp4").read_text(), "mp4 \n")
        self.assertEqual(self.listing(self.run), ["appear.mp4", "appear.take", "launches.txt"])
        self.assertEqual(self.calls()[:3], [
            "xcrun simctl io %s recordVideo --codec h264 --force %s" % (self.sim, self.run / ".pending" / "appear.mp4"),
            "Recording started",
            "axe tap --udid %s --wait-timeout 3 -x 5 -y 6" % self.sim,
        ], "the drive ran only after the recorder said it was capturing")
        self.assertEqual(self.calls().count("axe describe-ui --udid %s" % self.sim), 1,
                         "screen_pt= and card_pt= come from one describe after the take")

    def test_a_take_whose_tree_holds_no_active_set_card_stamps_card_pt_none(self):
        self.launch()
        tree = json.loads(MINI)
        tree[0]["children"] = [node for node in tree[0]["children"] if node.get("AXUniqueId") != "active-set-card"]
        (self.tmp / "describe-ui.json").write_text(json.dumps(tree))
        code, _, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual((dict(self.stamp())["screen_pt"], dict(self.stamp())["card_pt"]), ("402x874", "none"))
        self.assertEqual(self.calls().count("axe describe-ui --udid %s" % self.sim), 1)

    def test_a_tree_whose_card_frame_cannot_be_read_keeps_nothing_and_exits_70_naming_doctor(self):
        self.launch()
        tree = json.loads(MINI)
        card = next(node for node in tree[0]["children"] if node.get("AXUniqueId") == "active-set-card")
        del card["frame"]
        (self.tmp / "describe-ui.json").write_text(json.dumps(tree))
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, out, err.splitlines()[-1]), (70, "", (
            "could not read active-set-card's frame from the accessibility tree after the take, so appear.take "
            "cannot say where the card is; run: %s doctor" % self.verify_path)))
        self.assertEqual(self.listing(self.run), [".pending", "launches.txt"])
        self.assertEqual(self.listing(self.run / ".pending"), [])
        self.assertEqual(self.calls().count("axe describe-ui --udid %s" % self.sim), 1)

    def test_load_over_the_limit_after_the_take_keeps_it_and_exits_3_with_the_reason(self):
        self.launch()
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6", STUB_LOAD_AFTER="63.20")
        self.assertEqual((code, err), (3, "load 63.2 at the end, at or over 50\n"))
        self.assertEqual(SUMMARY.match(out.splitlines()[2]).groups(), ("INVALID", "63.2"))
        values = dict(self.stamp())
        self.assertEqual((values["verdict"], values["invalid"], values["invalid_rules"]),
                         ("INVALID", "load 63.2 at the end, at or over 50", "load"))
        self.assertEqual(self.listing(self.run), ["appear.mp4", "appear.take", "launches.txt"])

    def test_load_over_the_limit_before_the_take_refuses_with_no_recorder_and_no_drive(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_LOAD_BEFORE="63.20", VERIFY_LOAD_WAIT="0"),
                         (75, "", "load 63.20 at or over 50 after 0s; nothing recorded or driven\n"))
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.listing(self.run), ["launches.txt"])

    def test_load_that_stays_over_the_limit_is_waited_on_then_refused(self):
        self.launch()
        self.assertEqual(self.record(STUB_LOAD_BEFORE="50", VERIFY_LOAD_WAIT="1"), (75, "", (
            "load 50 at or over 50; waiting up to 1s for it to fall\n"
            "load 50 at or over 50 after 1s; nothing recorded or driven\n")))
        self.assertEqual(self.calls(), [])

    def test_a_run_that_takes_the_simulator_while_record_waits_for_load_is_refused_after_the_wait(self):
        self.launch()
        other = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(other.wait)
        self.addCleanup(other.kill)
        state = Path("/tmp/workout-verify-%s" % self.sim)
        (self.tmp / "bin" / "sysctl").write_text(CLAIMING_SYSCTL_STUB.replace("{dir}", str(self.tmp)).replace(
            "{state}", str(state)).replace("{pid}", str(other.pid)))
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", VERIFY_LOAD_WAIT="1"), (75, "", (
            "load 63.20 at or over 50; waiting up to 1s for it to fall\n"
            "the app on %s belongs to run lane-2 (pid %d), not to lane-1, so this would drive another run's app; "
            "launch yours first: SIM=%s VERIFY_RUN=lane-1 %s launch <fixture>\n"
            % (self.sim, other.pid, self.sim, self.verify_path))))
        self.assertEqual(self.calls(), [])

    def test_a_take_of_a_launch_refused_for_another_runs_app_hints_that_launch_as_given(self):
        app = self.own_the_app("owner-1")
        for drive, hint in [(["launch", "--animated", "session"], "launch --animated session"),
                            (["launch", "--at", "abc123", "--animated", "session"],
                             "launch --at abc123 --animated session"),
                            (["launch", "session"], "launch session"),
                            (["tap", "-x", "5", "-y", "6"], "launch <fixture>")]:
            with self.subTest(drive=drive):
                self.assertEqual(self.record("--", *drive), (75, "", (
                    "the app on {sim} belongs to run owner-1 (pid {pid}), not to lane-1, so this would drive another "
                    "run's app; launch yours first: SIM={sim} VERIFY_RUN=lane-1 {verify} {hint}\n"
                ).format(sim=self.sim, pid=app.pid, verify=self.verify_path, hint=hint)))
                self.assertEqual(self.calls(), [])

    def test_a_take_of_a_launch_refused_after_a_refused_relaunch_hints_that_launch_as_given(self):
        self.verify("install", self.a)
        self.own_the_app("ui12")
        refusal = "app on %s unchanged: %s; this launch wanted %s" % (
            self.sim, self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 75)
        for drive, hint in [(["launch", "--at", "abc123", "--animated", "session"],
                             "launch --at abc123 --animated session"),
                            (["tap", "-x", "5", "-y", "6"], "launch <fixture>")]:
            with self.subTest(drive=drive):
                self.assertEqual(self.record("--", *drive, VERIFY_RUN="ui12"), (75, "", (
                    "the last launch of run ui12 on {sim} was refused, so this would drive whatever that refusal left "
                    "running ({refusal}); stop it, then launch again: SIM={sim} VERIFY_RUN=ui12 {verify} stop, then "
                    "SIM={sim} VERIFY_RUN=ui12 {verify} {hint}\n"
                ).format(sim=self.sim, refusal=refusal, verify=self.verify_path, hint=hint)))
                self.assertEqual(self.calls(), [])

    def test_a_recorder_that_never_starts_capturing_drives_nothing_and_leaves_nothing(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_NEVER_STARTS="1", VERIFY_RECORD_START="1"),
                         (70, "", "simctl recordVideo did not start capturing within 1 s, so nothing was driven\n"))
        self.assertEqual(self.calls(), [
            "xcrun simctl io %s recordVideo --codec h264 --force %s" % (self.sim, self.run / ".pending" / "appear.mp4")])
        self.assertEqual(self.signals(), "INT\n")
        self.assertEqual(self.listing(self.run), [".pending", "launches.txt"])
        self.assertEqual(self.listing(self.run / ".pending"), [])

    def test_a_failing_drive_stops_the_recorder_and_leaves_nothing(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_AXE_EXIT="4"),
                         (1, "", "the drive `tap -x 5 -y 6` exited 4, so the take is not kept\n"))
        self.assertEqual(self.signals(), "INT\n")
        self.assertEqual(self.listing(self.run), [".pending", "launches.txt"])
        self.assertEqual(self.listing(self.run / ".pending"), [])

    def test_a_wrapped_launch_lands_in_the_takes_own_run(self):
        code, out, err = self.record("--", "launch", "--animated", "session", VERIFY_RUN="")
        self.assertEqual(code, 0, err)
        run = Path(out.splitlines()[0]).parent
        head = self.worktree_build(b"v2\n", self.b)
        self.assertEqual(err, "launched session as pid 4121 on %s (animations on)\n%s\nevidence %s\n" % (
            self.sim, head, run), "the drive's output goes to stderr, and it launched into the take's run")
        self.assertEqual(self.listing(run), ["appear.mp4", "appear.take", "launches.txt"])
        self.assertRegex((run / "launches.txt").read_text(), r"^\S+ session animated %s on %s from %s\n$" % (
            re.escape(head), self.sim, re.escape(str(self.checkout))))
        values = dict(self.stamp(run))
        self.assertEqual((values["drive"], values["animations"]), ("launch --animated session", "on"))

    def test_a_take_of_an_app_launched_without_animated_says_it_cannot_show_motion(self):
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 0)
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, err), (0, "animations are off in this app (it was launched without --animated), "
                                          "so the take cannot show motion\n"))
        self.assertEqual(dict(self.stamp())["animations"], "off")

    def test_a_rerun_replaces_the_pair(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_MARK="first")[0], 0)
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_MARK="second",
                                     STUB_PTS="1.250000 0.000000")[0], 0)
        self.assertEqual(self.listing(self.run), ["appear.mp4", "appear.take", "launches.txt"])
        self.assertEqual((self.run / "appear.mp4").read_text(), "mp4 second\n")
        values = dict(self.stamp())
        self.assertEqual((values["frames"], values["last_frame"]), ("2", "1.250"))

    def test_a_tail_that_is_not_a_number_is_usage_before_anything_runs(self):
        code, out, err = self.verify("record", "appear", "--tail", "2s", VERIFY_RUN="lane-1")
        self.assertEqual((code, out, err.splitlines()[0]), (2, "", "Usage: .agents/skills/verify/verify.sh <command> [args]"))
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
