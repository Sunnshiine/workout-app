from evidence_support import *  # noqa: F401,F403


class TapPoint(unittest.TestCase):
    """Issue 698: the point is the centre of the part of the frame the screen and its clips show."""

    def test_a_row_half_below_the_fold_is_tapped_in_its_visible_half(self):
        tree = on_screen_of_402x874(WIDE_CARD, HALF_ROW)
        row = "AXButton\thalf-row\tRow\t\t@23,850 312x52\n"
        self.assertEqual(tree_py("tappable", "half-row", stdin=tree), (0, "179 862\n" + row, ""),
                         "the frame centre is y 876, past the 874-point screen; y 850 to 874 is drawn")
        self.assertEqual(tree_py("tappable", "--label", "Row", stdin=tree), (0, "179 862\n" + row, ""),
                         "tap --label resolves through the same point")
        self.assertEqual(tree_py("find", "half-row", stdin=tree), (0, row, ""), "find still calls it on screen")

    def test_a_card_wider_than_the_screen_is_tapped_on_the_screen(self):
        self.assertEqual(tree_py("tappable", "active-set-card", stdin=on_screen_of_402x874(WIDE_CARD, HALF_ROW)),
                         (0, "201 630\nAXGroup\tactive-set-card\t\t\t@-83,476 4770x308\n", ""),
                         "the frame centre is x 2302 on a 402-point screen")

    def test_a_chip_across_the_track_edge_is_tapped_inside_the_track(self):
        tree = on_screen_of_402x874({
            "role": "AXGroup", "AXLabel": "RPE", "frame": {"x": 207, "y": 612, "width": 163, "height": 83},
            "children": [{"role": "AXButton", "AXUniqueId": "rpe-7", "AXLabel": "RPE 7",
                          "frame": {"x": 365, "y": 629, "width": 9, "height": 24}}],
        })
        self.assertEqual(tree_py("tappable", "rpe-7", stdin=tree)[:2], (0, "368 641\nAXButton\trpe-7\tRPE 7\t\t@365,629 9x24\n"),
                         "issue 703: the centre 369.5 printed as 370, the track's exclusive edge; x 365 to 370 is drawn")

    def test_the_printed_point_is_rounded_into_the_element(self):
        sliver = {"role": "AXButton", "AXUniqueId": "sliver", "frame": {"x": 369, "y": 629, "width": 1, "height": 24}}
        self.assertEqual(tree_py("tappable", "sliver", stdin=on_screen_of_402x874(sliver))[:2],
                         (0, "369 641\nAXButton\tsliver\t\t\t@369,629 1x24\n"),
                         "its centre 369.5 rounds to 370, which is past its right edge")

    def test_an_element_with_no_whole_point_on_the_screen_is_off_screen(self):
        sliver = {"role": "AXButton", "AXUniqueId": "sliver", "frame": {"x": 0, "y": 873.5, "width": 300, "height": 40}}
        self.assertEqual(tree_py("tappable", "sliver", stdin=on_screen_of_402x874(sliver)),
                         (1, "", "off-screen: swipe it into view before tapping\n"),
                         "y 873.5 to 874 is on the screen, but no whole point of it is")
        code, out, err = tree_py("flat", stdin=on_screen_of_402x874(sliver))
        self.assertEqual((code, out), (0, ""), "tree leaves out what find and tappable call off-screen")
        self.assertIn("1 off-screen element", err, "and counts it among the off-screen ones")

    def test_an_element_whose_drawn_part_is_outside_its_clip_is_refused(self):
        tree = on_screen_of_402x874({
            "role": "AXScrollArea", "frame": {"x": 0, "y": 880, "width": 402, "height": 100},
            "children": [{"role": "AXButton", "AXUniqueId": "straddling-row",
                          "frame": {"x": 0, "y": 860, "width": 402, "height": 40}}],
        })
        clipped = "clipped: outside AXScrollArea @0,880 402x100; bring it inside that frame before tapping\n"
        self.assertEqual(tree_py("tappable", "straddling-row", stdin=tree), (1, "", clipped),
                         "its centre y 880 is in the scroll area, but the part on the screen, y 860 to 874, is above it")
        self.assertEqual(tree_py("find", "straddling-row", stdin=tree)[::2], (0, clipped), "find says what tappable refuses")
