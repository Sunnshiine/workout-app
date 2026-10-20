from evidence_support import *  # noqa: F401,F403


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

    def test_an_unnamed_field_prints_with_empty_id_and_label_columns(self):
        code, out, err = tree_py("flat", stdin=NAMELESS_FIELD)
        self.assertEqual(code, 0, err)
        self.assertIn("AXTextField\t\t\tGoogle Sheet URL\t@32,459 338x34", out.splitlines(),
                      "issue 666: a field with no name is still on the screen, so the plain tree shows it")
        self.assertNotIn("AXGroup\t\t\t\t@0,0 402x874", out.splitlines(), "a bare layout group stays out")
        self.assertEqual(err, (
            "2 off-screen elements hidden; `verify.sh tree --all` lists them\n"
            "1 unnamed layout element with no value hidden; `verify.sh tree --all` lists them\n"
        ), "each kind of drop is counted, so a missing line is never read as a missing element")

    def test_all_prints_every_unnamed_node(self):
        code, out, err = tree_py("flat", "--all", stdin=NAMELESS_FIELD)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[-2:], [
            "AXGroup\t\t\t\t@0,0 402x874",
            "AXTextField\t\t\tGoogle Sheet URL\t@32,459 338x34",
        ])
        self.assertEqual(err, "")

    def test_unnamed_readable_roles_print_and_unnamed_groups_with_a_value_print(self):
        tree = json.loads(MINI)
        tree[0]["children"] = [
            {"role": role, "frame": {"x": 10, "y": 10 + 40 * n, "width": 30, "height": 30}}
            for n, role in enumerate(["AXButton", "AXStaticText", "AXImage", "AXSwitch", "AXSlider", "AXOther"])
        ] + [{"role": "AXGroup", "AXValue": "50%", "frame": {"x": 10, "y": 300, "width": 30, "height": 30}}]
        code, out, err = tree_py("flat", stdin=json.dumps(tree))
        self.assertEqual([line.split("\t")[0] for line in out.splitlines()[1:]],
                         ["AXButton", "AXStaticText", "AXImage", "AXSwitch", "AXSlider", "AXGroup"])
        self.assertEqual(err, "1 unnamed layout element with no value hidden; `verify.sh tree --all` lists them\n")

    def test_find_and_tap_never_resolve_an_unnamed_line(self):
        self.assertEqual(tree_py("find", "Google Sheet URL", stdin=NAMELESS_FIELD), (1, "", ""))
        self.assertEqual(tree_py("find", "", stdin=NAMELESS_FIELD)[0], 1, "an empty id is not the unnamed field's id")
        self.assertEqual(tree_py("center", "", stdin=NAMELESS_FIELD)[0], 1)
        self.assertEqual(tree_py("frame-of", "", stdin=NAMELESS_FIELD), (0, "none\n", ""))
        self.assertEqual(tree_py("tappable", "--label", "Google Sheet URL", stdin=NAMELESS_FIELD),
                         (1, "", "no element with label Google Sheet URL\n"))
        self.assertEqual(tree_py("tappable", "", stdin=NAMELESS_FIELD), (1, "", "no element with id \n"))

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

    def test_the_captured_trees_keep_what_has_a_whole_point_on_the_screen(self):
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
