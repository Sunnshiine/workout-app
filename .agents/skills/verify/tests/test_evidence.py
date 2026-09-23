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


def verify_sh(*args, run, sim=None):
    env = dict(os.environ)
    env.pop("VERIFY_RUN", None)
    env.pop("SIM", None)
    if run:
        env["VERIFY_RUN"] = run
    if sim:
        env["SIM"] = sim
    done = subprocess.run(
        [str(SKILL / "verify.sh")] + list(args), cwd=str(REPO), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr


def write_png(path, width, height, colour):
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
        self.assertEqual(out, "201 564\n", "the point verify.sh hands to axe")
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
        self.assertEqual(out, "200 220\n", "the scrolled-out twin is not a reason to refuse a tap that lands")


SESSION_RAILS = (FIXTURES / "session-rails.describe-ui.json").read_text()
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
        self.assertEqual(tree_py("tappable", "rpe-6.5", stdin=SESSION_RAILS)[1:], ("336 641\n", ""))
        self.assertEqual(tree_py("tappable", "rpe-6", stdin=SESSION_RAILS)[1:], ("289 641\n", ""))
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
        self.assertEqual(tree_py("tappable", "rpe-7", stdin=rpe_7_at(364))[:2], (0, "368 641\n"),
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

    def test_on_the_captured_screen_exactly_the_chips_a_tap_misses_are_clipped(self):
        on_screen = [line.split("\t")[1] for line in tree_py("flat", stdin=SESSION_RAILS)[1].splitlines()]
        clipped = [ident for ident in on_screen if ident and "clipped" in tree_py("find", ident, stdin=SESSION_RAILS)[2]]
        self.assertEqual(clipped, ["reps-3", "reps-7", "reps-8", "reps-9", "reps-10", "reps-11", "rpe-7"],
                         "describe-ui --point at each centre on the live app returned something else for these seven")


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

    def test_launch_refuses_an_unknown_fixture_before_any_simulator_is_touched(self):
        code, out, err = verify_sh("launch", "no-such-fixture", run=self.run, sim="no-such-device")
        self.assertEqual(code, 2, err)
        self.assertIn("unknown fixture: no-such-fixture", err)
        self.assertEqual(out, "", "nothing was launched")

    def test_sheet_refuses_an_argument_it_would_ignore(self):
        code, out, err = verify_sh("sheet", "02-after-log", run=self.run)
        self.assertEqual(code, 2, "sheet tiles the whole run; a stray name must not look accepted: %s" % err)
        self.assertEqual(out, "")

    def test_tap_says_usage_for_a_flag_left_without_its_value(self):
        for argv in [["tap", "--id"], ["tap", "--wait-timeout"], ["tap", "--label", "Save", "--wait-timeout"]]:
            code, out, err = verify_sh(*argv, run=self.run, sim="no-such-device")
            self.assertEqual(code, 2, "%s must print usage, not die on its own shift: %s" % (argv, err))
            self.assertIn("Usage:", err)

    def test_tap_by_id_refuses_a_wait_timeout_it_cannot_count(self):
        code, out, err = verify_sh(
            "tap", "--id", "weight-pill", "--wait-timeout", "1.5", run=self.run, sim="no-such-device")
        self.assertEqual(code, 2, "the poll budget is counted in whole seconds: %s" % err)
        self.assertIn("whole seconds", err)
        self.assertEqual(out, "", "refused before any simulator is touched")

    def test_shot_refuses_a_name_that_could_collide(self):
        for name in ["_sheet", "a.burst", "-x"]:
            code, out, err = verify_sh("shot", name, run=self.run)
            self.assertEqual(code, 2, "%s must be refused before any simulator is touched: %s" % (name, err))


class VerifyStop(unittest.TestCase):
    def setUp(self):
        self.owner = "owner-%d" % os.getpid()
        self.sim = "no-such-device-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("%s\n" % self.owner)
        (self.state / "pid").write_text("99999999\n")

    def tearDown(self):
        shutil.rmtree(self.state, ignore_errors=True)

    def test_stop_refuses_to_end_a_run_that_is_not_the_callers(self):
        code, out, err = verify_sh("stop", run="issue-660", sim=self.sim)
        self.assertEqual(code, 75, "the code launch already uses for a simulator another run owns")
        self.assertIn(self.owner, err, "whose app it is about to end")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err, "the override, spelled out")
        self.assertEqual(out, "", "nothing was terminated")
        self.assertTrue((self.state / "pid").exists(), "the owner keeps the pid it recorded")

    def test_stop_ends_the_callers_own_run(self):
        code, out, err = verify_sh("stop", run=self.owner, sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertFalse((self.state / "pid").exists(), "its own stop clears the pid it recorded")

    def test_stop_on_a_simulator_no_run_has_claimed_is_not_refused(self):
        shutil.rmtree(self.state)
        code, out, err = verify_sh("stop", run="issue-660", sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertIn("nothing launched by this tool", out, "a fresh simulator is nobody's")

    def test_stop_without_a_run_name_is_still_allowed(self):
        code, out, err = verify_sh("stop", run=None, sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertFalse(
            (self.state / "pid").exists(),
            "with no VERIFY_RUN the guard has nothing to compare against, so it steps aside and "
            "the ordinary single drive keeps working",
        )


@unittest.skipUnless(sys.platform == "darwin", "the tiler is a Swift script and runs on macOS only")
class VerifySheet(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
