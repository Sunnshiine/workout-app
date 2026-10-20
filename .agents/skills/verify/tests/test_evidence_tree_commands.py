from evidence_support import *  # noqa: F401,F403


GEAR = "AXButton\tsession-controls-settings-button\tSettings\t\t@334,65 44x44"
WEIGHT_PILL = "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66"


class Landing(unittest.TestCase):
    def test_the_target_itself_at_its_centre_lands(self):
        self.assertEqual(tree_py("landing", GEAR, APP, "356", "87", stdin=GEAR_UP), (0, "", ""), "the live read with the controls up")
        self.assertEqual(tree_py("landing", GEAR.replace("@334,65", "@334,40"), APP, "356", "62", stdin=GEAR_UP), (0, "", ""),
                         "its own id lands even when its frame moved between the two reads")

    def test_a_child_inside_the_target_lands(self):
        child = [{"role": "AXStaticText", "AXLabel": "237.5", "pid": 53393,
                  "frame": {"x": 110, "y": 545, "width": 180, "height": 40}}]
        self.assertEqual(tree_py("landing", WEIGHT_PILL, APP, "201", "564", stdin=json.dumps(child)), (0, "", ""),
                         "the text drawn inside the pill wins the hit test, and the tap still lands on the pill")

    def test_the_alert_backdrop_over_the_sign_out_row_is_covered(self):
        backdrop = (FIXTURES / "sign-out-row-under-alert.describe-ui.json").read_text()
        row = "AXButton\tsettings-sign-out-button\tSign Out\t\t@16,657 370x52"
        self.assertEqual(tree_py("landing", row, "62389", "201", "683", stdin=backdrop), (1, "", (
            "covered: at 201,683 the screen has AXGroup @0,0 402x874, not AXButton settings-sign-out-button" + COVERED
        )), "the full tree still lists the row under the alert; the live point read returned the backdrop")

    def test_the_header_text_where_the_hidden_gear_was_is_covered(self):
        self.assertEqual(tree_py("landing", GEAR, APP, "356", "87", stdin=GEAR_HIDDEN), (1, "", GEAR_COVERED),
                         "the controls hid 2.5 s after the drag, between the tree read and the point read")

    def test_nothing_at_the_point_is_covered(self):
        for answer in ["", "[]"]:
            with self.subTest(answer=answer):
                self.assertEqual(tree_py("landing", WEIGHT_PILL, APP, "201", "564", stdin=answer), (
                    1, "", "covered: at 201,564 the screen has nothing, not AXButton weight-pill" + COVERED))

    def test_the_note_names_the_point_tapped_not_the_frame_centre(self):
        self.assertEqual(tree_py("landing", WEIGHT_PILL, APP, "110", "540", stdin=""), (
            1, "", "covered: at 110,540 the screen has nothing, not AXButton weight-pill" + COVERED),
            "tappable may aim off the centre, at the part of the pill the screen shows")

    def test_a_landing_without_the_point_tapped_is_refused(self):
        code, out, err = tree_py("landing", WEIGHT_PILL, APP, stdin="")
        self.assertEqual((code, out), (1, ""), "no point to name, so no landing to judge")
        self.assertIn("tree.py landing LINE FRONT_PID X Y", err, "the usage names the point it needs")

    def test_a_frame_within_a_point_of_the_printed_edges_lands(self):
        done = "AXButton\t\tDone\t\t@316,66 66x36"

        def hit_at(x):
            return json.dumps({"role": "AXStaticText", "AXLabel": "Done", "pid": 53393,
                               "frame": {"x": x, "y": 65.667, "width": 65.667, "height": 36.333}})

        self.assertEqual(tree_py("landing", done, APP, "349", "84", stdin=hit_at(316.333)), (0, "", ""),
                         "the button's own fractional frame, printed as @316,66 66x36")
        self.assertEqual(tree_py("landing", done, APP, "349", "84", stdin=hit_at(317)), (0, "", ""),
                         "a child whose right edge, 382.667, passes the printed 382 by less than a point")
        self.assertEqual(tree_py("landing", done, APP, "349", "84", stdin=hit_at(314.6)), (1, "", (
            "covered: at 349,84 the screen has AXStaticText Done @315,66 66x36, not AXButton Done" + COVERED
        )), "a frame more than a point past the left edge is something else")

    def test_a_point_read_from_another_process_over_the_app_is_covered(self):
        for hit in [{"role": "AXButton", "AXLabel": "Allow", "pid": 111}, {"role": "AXButton", "AXLabel": "Allow"}]:
            with self.subTest(pid=hit.get("pid")):
                hit["frame"] = {"x": 334, "y": 65, "width": 44, "height": 44}
                self.assertEqual(tree_py("landing", GEAR, APP, "356", "87", stdin=json.dumps(hit)), (1, "", (
                    "covered: at 356,87 the screen has AXButton Allow @334,65 44x44, "
                    "not AXButton session-controls-settings-button" + COVERED
                )), "a system prompt the size of the gear, or a hit with no process, is not the app's gear")



CROP_USAGE = "usage: tree.py crop SHOT.tree.txt PNG_WIDTH ID | crop SHOT.tree.txt PNG_WIDTH X Y W H\n"


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
