from evidence_support import *  # noqa: F401,F403


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
        self.assertEqual(tree_py("tappable", "rpe-7", stdin=rpe_7_at(364))[:2], (0, "367 641\nAXButton\trpe-7\tRPE 7\t\t@364,629 9x24\n"),
                         "x 364 to 373 pokes past the track, so the tap goes to the middle of x 364 to 370")

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
            "2 elements carry the label RPE; pick one by its id, or tap it with -x -y:",
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
            "2 elements carry the label Sign Out; pick one by its id, or tap it with -x -y:",
            "AXButton\tsettings-sign-out-button\tSign Out\t\t@16,657 370x52\t-x 201 -y 683",
            "AXButton\t\tSign Out\t\t@205,484 140x48\t-x 275 -y 508",
        ], "the Settings row behind the alert, then the alert's own button")

    def test_a_label_nothing_carries_is_named(self):
        self.assertEqual(tree_py("tappable", "--label", "Sign out", stdin=SETTINGS),
                         (1, "", "no element with label Sign out\n"), "the match is case-sensitive")

    def test_a_blank_label_matches_nothing(self):
        self.assertEqual(tree_py("tappable", "--label", " ", stdin=MINI), (1, "", "no element with label  \n"),
                         "active-set-card has an id and no label, and a blank query must not reach it")
