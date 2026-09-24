#!/usr/bin/env python3
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
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


def verify_sh(*args, run, sim=None, path=None):
    env = dict(os.environ)
    env.pop("VERIFY_RUN", None)
    env.pop("SIM", None)
    if run:
        env["VERIFY_RUN"] = run
    if sim:
        env["SIM"] = sim
    if path:
        env["PATH"] = path
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

    def test_a_zero_size_group_in_the_keyboard_toolbar_does_not_clip_done(self):
        done = "AXButton\tweight-keyboard-done\tDone\t\t@319,798 62x36\n"
        self.assertEqual(tree_py("find", "weight-keyboard-done", stdin=KEYBOARD_DONE), (0, done, ""),
                         "an AXGroup @16,792 0x0 sits between the toolbar and Done, and Done is drawn")
        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=KEYBOARD_DONE), (0, "350 816\n", ""),
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

        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=group_sized(0, 48)), (0, "350 816\n", ""))
        self.assertEqual(tree_py("tappable", "weight-keyboard-done", stdin=group_sized(370, 0)), (0, "350 816\n", ""))
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
        self.assertEqual(tree_py("tappable", "WorkoutTracker", stdin=HOME_SCREEN), (0, "62 336\n", ""),
                         "live-activity.md reopens the app with tap --id WorkoutTracker; the icon sits in an AXButton @0,0 0x0")

    def test_on_the_captured_screen_exactly_the_chips_a_tap_misses_are_clipped(self):
        on_screen = [line.split("\t")[1] for line in tree_py("flat", stdin=SESSION_RAILS)[1].splitlines()]
        clipped = [ident for ident in on_screen if ident and "clipped" in tree_py("find", ident, stdin=SESSION_RAILS)[2]]
        self.assertEqual(clipped, ["reps-3", "reps-7", "reps-8", "reps-9", "reps-10", "reps-11", "rpe-7"],
                         "describe-ui --point at each centre on the live app returned something else for these seven")


class TappableByLabel(unittest.TestCase):
    def test_a_label_on_one_enabled_on_screen_element_is_its_centre(self):
        self.assertEqual(tree_py("tappable", "--label", "Weight, 237.5", stdin=MINI), (0, "201 564\n", ""))

    def test_a_control_wins_over_the_text_that_shares_its_label(self):
        for label, point in [("Developer Tools", "201 596\n"), ("Standard, 2:00", "201 353\n")]:
            with self.subTest(label=label):
                self.assertEqual(tree_py("tappable", "--label", label, stdin=SETTINGS), (0, point, ""))

    def test_a_label_only_a_text_carries_is_that_texts_centre(self):
        self.assertEqual(tree_py("tappable", "--label", "Standard", stdin=SETTINGS), (0, "67 353\n", ""))

    def test_spaces_around_the_label_are_trimmed(self):
        self.assertEqual(tree_py("tappable", "--label", "  Sign Out ", stdin=SETTINGS), (0, "201 683\n", ""))

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


FAKE_AXE = """#!/bin/sh
case $1 in
  describe-ui) cat "{dir}/describe-ui.json" ;;
  tap) printf '%s\\n' "$*" >> "{dir}/calls"; echo "Tap completed" ;;
  *) exit 64 ;;
esac
"""


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
        self.sim = "tap-test-%d" % os.getpid()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def tap(self, tree, *args):
        (self.root / "describe-ui.json").write_text(tree)
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
                         (1, "", "off-screen: swipe it into view before tapping\n", []))

    def test_a_label_tree_py_resolves_is_tapped_once_at_its_centre(self):
        self.assertEqual(self.tap(SETTINGS, "--label", "Developer Tools", "--wait-timeout", "0"),
                         (0, "Tap completed\n", "", ["tap --udid %s -x 201 -y 596" % self.sim]))

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
        self.sim = "no-such-device-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("%s\n" % self.owner)
        (self.state / "pid").write_text("99999999\n")

    def tearDown(self):
        shutil.rmtree(self.state, ignore_errors=True)

    def launched_with_live_activities(self):
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_ANIMATIONS\n")

    def test_stop_refuses_to_end_a_run_that_is_not_the_callers(self):
        (self.state / "pid").write_text("%d\n" % os.getpid())
        code, out, err = verify_sh("stop", run="issue-660", sim=self.sim)
        self.assertEqual(code, 75, "the code launch already uses for a simulator another run owns")
        self.assertIn(self.owner, err, "whose app it is about to end")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err, "the override, spelled out")
        self.assertEqual(out, "", "nothing was terminated")
        self.assertTrue((self.state / "pid").exists(), "the owner keeps the pid it recorded")

    def test_stop_ends_the_callers_own_run(self):
        self.launched_with_live_activities()
        code, out, err = verify_sh("stop", run=self.owner, sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err, "its own stop goes on to the uninstall")
        self.assertFalse((self.state / "pid").exists(), "its own stop clears the pid it recorded")

    def test_stop_refuses_to_uninstall_a_live_activity_run_that_is_not_the_callers(self):
        self.launched_with_live_activities()
        code, out, err = verify_sh("stop", run=self.next, sim=self.sim)
        self.assertEqual(code, 75, "its app died, but stop would still uninstall it and end the run's Live Activity")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err)
        self.assertTrue((self.state / "args").exists(), "the owner's own stop can still uninstall")

    def test_a_dead_pid_that_stop_would_only_forget_is_not_refused(self):
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        code, out, err = verify_sh("stop", run=self.next, sim=self.sim)
        self.assertEqual((code, out, err), (0, "", ""))
        self.assertFalse((self.state / "pid").exists(), "no app and no Live Activity, so nothing to protect")

    def test_a_dead_pid_with_no_args_is_not_refused(self):
        code, out, err = verify_sh("stop", run=self.next, sim=self.sim)
        self.assertEqual(
            (code, out, err), (0, "", ""),
            "a launch cut off after its pid write recorded no opt-in, so no stop would uninstall this app",
        )
        self.assertFalse((self.state / "pid").exists())

    def test_after_the_owners_stop_the_next_runs_stop_is_not_refused(self):
        code, out, err = verify_sh("stop", run=self.owner, sim=self.sim)
        self.assertEqual(code, 0, err)
        code, out, err = verify_sh("stop", run=self.next, sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "nothing launched by this tool on %s\n" % self.sim)

    def test_an_unnamed_diff_after_stop_still_reads_the_runs_shots(self):
        evidence = REPO / ".build" / "verify" / "evidence" / self.owner
        evidence.mkdir(parents=True, exist_ok=True)
        self.addCleanup(shutil.rmtree, evidence, True)
        for name in ["01-before", "02-after-log"]:
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), evidence / ("%s.tree.txt" % name))
        verify_sh("stop", run=self.owner, sim=self.sim)
        code, out, err = verify_sh("diff", "01-before", "02-after-log", run=None, sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())

    def test_stop_on_a_simulator_no_run_has_claimed_is_not_refused(self):
        (self.state / "run").unlink()
        self.launched_with_live_activities()
        code, out, err = verify_sh("stop", run="issue-660", sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err, "an app no run has claimed is nobody's")

    def test_stop_without_a_run_name_is_still_allowed(self):
        self.launched_with_live_activities()
        code, out, err = verify_sh("stop", run=None, sim=self.sim)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err)
        self.assertFalse(
            (self.state / "pid").exists(),
            "with no VERIFY_RUN the guard has nothing to compare against, so it steps aside and "
            "the ordinary single drive keeps working",
        )


STUB = """#!/bin/sh
printf '%s\\n' "$(basename "$0") $*" >> "{dir}/calls"
[ "$(basename "$0")" != xcodebuild ] || echo "** BUILD FAILED **"
[ -n "${STUB_HOLD:-}" ] || exit 1
touch "{dir}/holding"
i=0
while [ ! -f "{dir}/release" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
exit 1
"""
FIXTURE_APP = [sys.executable, "-c", "import time; time.sleep(60)", "-UITEST_FIXTURE"]


class SimulatorLock(unittest.TestCase):
    def setUp(self):
        self.sim = "lock-test-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        shutil.rmtree(self.state, ignore_errors=True)
        self.stubs = Path(tempfile.mkdtemp())
        for tool in ["xcodebuild", "xcrun", "npm", "plutil"]:
            (self.stubs / tool).write_text(STUB.replace("{dir}", str(self.stubs)))
            (self.stubs / tool).chmod(0o755)
        self.path = "%s:%s" % (self.stubs, os.environ["PATH"])
        self.runs = []

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
        return self.spawn([str(REPO / "scripts" / "test-sim.sh"), "--sim", self.sim, "unit"], hold)

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
        code, out, err = verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)
        self.assertEqual(code, 75, err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
        self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]],
                         "refused before any simulator is touched: no xcrun, no axe install")

    def test_test_sim_refuses_while_a_verify_run_owns_the_app(self):
        app = self.own_the_app("owner-626")
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 75, err)
        self.assertEqual(
            err,
            "a verify run owner-626 owns the app on %s (pid %d); if it is yours, run: SIM=%s VERIFY_RUN=owner-626 "
            "%s/.claude/skills/verify/verify.sh stop, else use another simulator\n" % (self.sim, app.pid, self.sim, REPO),
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
                            SIM=self.sim, VERIFY_RUN="issue-626")
        self.wait_for_hold(launch, "plutil")
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 75, err)
        self.assertIn("verify.sh launch (pid %d)" % launch.pid, err, "names the launch that holds it")
        self.assertEqual(self.first_words(), [["plutil", "-extract"]],
                         "the launch got as far as its app lookup, and test-sim.sh ran no xcodebuild")

    def test_stop_refuses_to_uninstall_while_a_test_sim_run_holds_the_simulator(self):
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("owner-626\n")
        (self.state / "pid").write_text("99999999\n")
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_ANIMATIONS\n")
        run = self.holding_test_sim()
        code, out, err = verify_sh("stop", run="owner-626", sim=self.sim, path=self.path)
        self.assertEqual(code, 75, "the uninstall would remove the app under test: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
        self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]], "no xcrun call")
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ["args", "lock", "pid", "run"],
                         "a later stop can still uninstall")
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        code, out, err = verify_sh("stop", run="owner-626", sim=self.sim, path=self.path)
        self.assertEqual(code, 0, err)
        self.assertEqual(self.calls()[-1], "xcrun simctl uninstall %s com.sunnypatel.WorkoutTracker" % self.sim)
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ["lock", "run"])

    def test_a_test_sim_run_holds_the_simulator_until_it_exits(self):
        run = self.holding_test_sim()
        self.assertEqual(verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)[0], 75)
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        self.assertEqual(run.returncode, 65, "the stub build failed, so the run ended")
        code, out, err = verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)
        self.assertNotEqual(code, 75, err)
        self.assertNotIn("test-sim.sh", err)

    def test_a_killed_test_sim_run_does_not_hold_the_simulator(self):
        killed = self.holding_test_sim()
        os.killpg(killed.pid, 9)
        killed.wait()
        run = self.holding_test_sim()
        code, out, err = verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)
        self.assertEqual(code, 75, err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "the live run holds it, not the killed one")

    def test_a_dead_verify_app_does_not_hold_the_simulator(self):
        self.own_the_app("owner-626")
        (self.state / "pid").write_text("99999999\n")
        run = self.holding_test_sim()
        code, out, err = verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)
        self.assertEqual(code, 75, "the test-sim.sh run went ahead and holds it now: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err)

    def test_shot_and_burst_refuse_while_a_test_sim_run_holds_the_simulator(self):
        run = self.holding_test_sim()
        name = "issue-626-%d" % os.getpid()
        evidence = REPO / ".build" / "verify" / "evidence" / name
        self.addCleanup(shutil.rmtree, evidence, True)
        for argv in [["shot", "01-mid-test"], ["burst", "log-transition"]]:
            code, out, err = verify_sh(*argv, run=name, sim=self.sim, path=self.path)
            self.assertEqual(code, 75, "%s would record the test run's screen: %s" % (argv[0], err))
            self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
            self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]],
                         "refused before any simulator is touched: no xcrun, no axe install")
        self.assertFalse(evidence.exists(), "no evidence directory for shots that were never taken")
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        for argv in [["shot", "02-after-test"], ["burst", "log-transition"]]:
            code, out, err = verify_sh(*argv, run=name, sim=self.sim, path=self.path)
            self.assertNotEqual(code, 75, "%s goes ahead once the test run is over: %s" % (argv[0], err))
            self.assertNotIn("is held", err)

    def test_the_xcodebuild_of_a_killed_test_sim_run_holds_the_simulator_until_it_exits(self):
        run = self.holding_test_sim()
        os.kill(run.pid, 9)
        run.wait()
        code, out, err = verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)
        self.assertEqual(code, 75, "its xcodebuild still drives the simulator: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "the run that started it")
        self.assertIn("lsof /tmp/workout-verify-%s/lock" % self.sim, err, "finds the xcodebuild its dead pid hides")
        self.assertEqual(out, "")
        (self.stubs / "release").touch()
        for _ in range(50):
            code, out, err = verify_sh("launch", "session", run="issue-626", sim=self.sim, path=self.path)
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
except BlockingIOError: print("held by " + open(sys.argv[1]).read().strip())
else: print("free")' "$lock")
printf '%s, lock %s\\n' "$(basename "$0") $*" "$held" >> "{dir}/calls"
case "$(basename "$0") $2" in
  "plutil WorkspacePath") echo "{project}" ;;
  "xcrun bootstatus")
    if [ -n "${STUB_HOLD:-}" ]; then echo $$ > "{dir}/holding"; exec sleep 30; fi
    exit "${STUB_BOOTSTATUS:-1}" ;;
  "xcrun list") ;;
  *) exit 1 ;;
esac
"""


class LaunchBoots(unittest.TestCase):
    def setUp(self):
        self.sim = "boot-test-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        shutil.rmtree(self.state, ignore_errors=True)
        self.home = Path(tempfile.mkdtemp())
        derived = self.home / "Library" / "Developer" / "Xcode" / "DerivedData" / "WorkoutTracker-test"
        (derived / "Build" / "Products" / "Debug-iphonesimulator" / "WorkoutTracker.app").mkdir(parents=True)
        self.plist = derived / "info.plist"
        self.plist.touch()
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

    def spawn(self, sim, **env):
        env = dict(os.environ, HOME=str(self.home), PATH="%s:%s" % (self.stubs, os.environ["PATH"]),
                   VERIFY_RUN="issue-676", **env)
        env.pop("SIM", None)
        if sim:
            env["SIM"] = sim
        run = subprocess.Popen(
            [str(SKILL / "verify.sh"), "launch", "session"], cwd=str(REPO), env=env, start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.runs.append(run)
        return run

    def launch(self, sim, **env):
        (self.stubs / "calls").unlink(missing_ok=True)
        run = self.spawn(sim, **env)
        out, err = run.communicate(timeout=30)
        calls = self.stubs / "calls"
        return run, calls.read_text().splitlines() if calls.exists() else [], (run.returncode, out, err)

    def test_launch_waits_on_the_boot_under_its_lock_and_installs_nothing_when_it_fails(self):
        for named in [self.sim, None]:
            with self.subTest(SIM=named):
                run, calls, result = self.launch(named)
                holder = "lock held by verify.sh launch (pid %d)" % run.pid
                self.assertEqual(calls, [
                    "plutil -extract WorkspacePath raw %s, %s" % (self.plist, holder),
                    "xcrun simctl bootstatus %s -b, %s" % (self.sim, holder),
                ], "the shut-down simulator is booted and waited on while the launch holds it, and never installed to")
                self.assertEqual(result, (70, "", "simulator %s did not boot\n" % self.sim))

    def test_a_boot_wait_that_ends_with_the_simulator_down_installs_nothing(self):
        run, calls, result = self.launch(self.sim, STUB_BOOTSTATUS="0")
        self.assertEqual(calls[1:], [
            "xcrun simctl bootstatus %s -b, lock held by verify.sh launch (pid %d)" % (self.sim, run.pid),
            "xcrun simctl list devices booted, lock held by verify.sh launch (pid %d)" % run.pid,
        ], "bootstatus exits 0 when a shutdown ends the boot, so the launch reads the state before it installs")
        self.assertEqual(result, (70, "", "simulator %s did not boot\n" % self.sim))

    def test_a_launch_killed_during_its_boot_wait_frees_the_simulator_at_once(self):
        killed = self.spawn(self.sim, STUB_HOLD="1")
        for _ in range(100):
            if (self.stubs / "holding").exists() or killed.poll() is not None:
                break
            time.sleep(0.1)
        self.assertTrue((self.stubs / "holding").exists(), "the launch never reached its boot wait")
        os.kill(killed.pid, 9)
        killed.wait()
        boot_wait = int((self.stubs / "holding").read_text())
        self.addCleanup(os.kill, boot_wait, 9)
        run, calls, result = self.launch(self.sim)
        os.kill(boot_wait, 0)
        self.assertEqual(result, (70, "", "simulator %s did not boot\n" % self.sim),
                         "the next launch takes the simulator while the killed one's boot wait still runs")


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
        self.sim = "shot-test-%d" % os.getpid()
        self.evidence = self.root / ".build" / "verify" / "evidence" / "issue-674"
        self.home, self.stage = self.root / "home.png", self.root / "stage.png"
        write_png(self.home, 4, 4, (32, 96, 160))
        write_png(self.stage, 4, 4, (240, 240, 240))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def shot(self, name, frame, tree):
        described = self.root / ("%s.describe-ui.json" % name)
        described.write_text(tree)
        env = dict(os.environ, SIM=self.sim, VERIFY_RUN="issue-674", STUB_FRAME=str(frame), STUB_TREE=str(described))
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
            "either the shot fired before a transition drew (wait a second and shoot again) or the screenshot "
            "pipeline is wedged, as the axe button lock in issue 674 left it "
            "(run: xcrun simctl shutdown %s, then %s launch <fixture>)\n" % (self.sim, self.verify)
        ))
        self.assertEqual(sorted(p.name for p in self.evidence.iterdir()), ["01-before.png", "01-before.tree.txt"],
                         "the frozen frame is not filed as evidence")
        code, out, err = self.shot("02-after-log", self.home, AFTER_LOG)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[-1], "2 changed, 3 unchanged", "shooting again once the frame moved lands")

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
