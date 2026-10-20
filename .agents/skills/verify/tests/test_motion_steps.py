from motion_support import *  # noqa: F401,F403


class LookOf(unittest.TestCase):
    def look(self, *insides):
        look = cardframe.look_of(looks(*insides), card(100))
        return round(look.peak, 3), look.frames, look.motion, look.kind

    def test_a_change_in_one_frame_is_a_cut(self):
        self.assertEqual(self.look(230, 230, 240, 240), (10.0, 1, (0.2, 0.2), LookKind.CUT))

    def test_a_change_over_several_frames_runs_from_the_first_that_left_to_the_first_that_stayed(self):
        self.assertEqual(self.look(200, 210, 220, 230, 240, 240), (40.0, 4, (0.1, 0.4), LookKind.CHANGED))

    def test_half_a_unit_from_the_last_frame_is_still_and_more_is_a_change(self):
        self.assertEqual(self.look(240.5, 240, 240.25, 240), (0.5, 0, None, LookKind.STILL))
        self.assertEqual(self.look(240.75, 240, 240), (0.75, 1, (0.1, 0.1), LookKind.CUT))

    def test_a_one_frame_flash_reads_as_a_change_spanning_both_cuts(self):
        self.assertEqual(self.look(240, 210, 240, 240), (30.0, 2, (0.1, 0.2), LookKind.CHANGED))

    def test_a_change_that_never_leaves_the_first_frame_by_half_a_unit_is_dated_where_it_settled(self):
        self.assertEqual(self.look(240.4, 240.75, 240), (0.75, 1, (0.2, 0.2), LookKind.CUT))

    def test_the_box_is_the_cells_wholly_inside_the_card(self):
        self.assertEqual(cardframe.box_cells(Card(481.3, 777.3, 16.0, 386.0, 12.2)), (slice(121, 194), slice(4, 96)))


class Ramp(unittest.TestCase):
    def test_a_change_over_three_quarters_of_the_tiles_is_the_fade_and_two_thirds_is_not(self):
        self.assertEqual(cardframe.changed_fraction(FLAT, lit(72)), 0.75)
        self.assertEqual(cardframe.changed_fraction(FLAT, lit(64)), 0.6666666666666666)
        self.assertEqual(cardframe.changed_fraction(FLAT, FLAT + 0.5), 0.0)

    def test_the_fade_starts_at_the_first_full_screen_frame_from_black_after_the_launch_and_ends_within_0_5_s(self):
        self.assertEqual(cardframe.launch_fade(FADED_IN, 0.05), (2, None))
        self.assertEqual(cardframe.launch_fade(FADED_IN, 0.65), None)
        self.assertEqual(cardframe.launch_fade(launch_frames(), 0.05), (12, None),
                         "past the springboard's fade-out, through the repeated frame, and not out to the card's slide")
        self.assertEqual(cardframe.launch_fade(launch_frames(dim=True), 0.05), (12, 17),
                         "a later dim is not the fade, and is the first full-screen frame after it")
        self.assertEqual(cardframe.launch_fade(launch_frames(from_black=False), 0.05), None)


class OpenWindow(unittest.TestCase):
    def test_each_way_a_window_opens(self):
        tap = dataclasses.replace(TAKE, drive="tap --id x", drive_start=0.65)
        self.assertEqual(cardframe.open_window(LAUNCH, FADED_IN, None), (Window(Opened.RAMP, 2, 0.6, 3.4), ()))
        self.assertEqual(cardframe.open_window(LAUNCH, FADED_IN, 0.75), (Window(Opened.FROM, 3, 0.75, 3.25), ()))
        self.assertEqual(cardframe.open_window(tap, FADED_IN, None), (Window(Opened.DRIVE, 2, 0.65, 2.35), ()))
        self.assertEqual(cardframe.open_window(TAKE, FADED_IN, None), (Window(Opened.START, 0, 0.0, 3.0), ()))

    def test_a_window_that_watched_under_1_5_s_says_so_whatever_the_take_s_tail(self):
        opened = [cardframe.open_window(dataclasses.replace(LAUNCH, stopped=stopped, tail=3.0), FADED_IN, None)
                  for stopped in (2.0, 2.5)]
        self.assertEqual([(round(window.seconds, 3), reasons) for window, reasons in opened], [
            (1.4, (Reason("window", "the window watched 1.40 s from +0.600 s, under 1.5 s"),)),
            (1.9, ()),
        ])

    def test_a_launch_window_opens_where_the_fade_from_black_ends(self):
        self.assertEqual(cardframe.open_window(LAUNCH, launch_frames(), None), (Window(Opened.RAMP, 12, 1.0, 3.0), ()))

    def test_a_full_screen_change_after_the_fade_from_black_makes_a_launch_take_invalid(self):
        self.assertEqual(cardframe.open_window(LAUNCH, launch_frames(dim=True), None), (
            Window(Opened.RAMP, 12, 1.0, 3.0),
            (Reason("screen", "a frame at +2.720 s changed three quarters of the screen after iOS's fade-in ended, "
                              "so the card cannot be read through it"),)))

    def test_a_launch_with_no_full_screen_frame_from_black_opens_at_the_drive_and_says_so(self):
        window, reasons = cardframe.open_window(LAUNCH, launch_frames(from_black=False), None)
        self.assertEqual((window.opened, [r.rule for r in reasons]), (Opened.DRIVE, ["ramp"]))

    def test_a_launch_with_no_fade_opens_at_the_drive_and_says_so(self):
        self.assertEqual(cardframe.open_window(LAUNCH, FADED_IN[2:], None), (Window(Opened.DRIVE, 0, 0.05, 3.95), (
            Reason("ramp", "no frame after the launch began changed three quarters of the screen, so iOS's fade-in "
                           "cannot be told from the app's motion"),)))


class BoxOf(unittest.TestCase):
    def test_a_faint_card_before_the_first_solid_one_is_counted_and_its_edges_not_read(self):
        box = cardframe.box_of(frames(card(90, contrast=5.0), card(95, contrast=29.9), card(100, contrast=30.0),
                                      card(100)), card(100))
        self.assertEqual((box.first_seen, box.faint, box.partial, box.ranges["top"], box.changed),
                         (0.2, 2, True, (100.0, 100.0), False))

    def test_an_eased_move_runs_from_the_first_card_half_a_point_away_to_the_first_that_stays_by_the_settled_one(self):
        tops = (100, 100.2, 100.8, 102.5, 105, 108, 111, 113.5, 115.2, 115.8, 116, 116)
        box = cardframe.box_of(frames(*(card(top) for top in tops)), card(116))
        self.assertEqual((box.motion, box.motion_ms, box.changed_frames, box.worst_edge_range),
                         ((0.2, 0.9), 700, 8, 16.0))

    def test_after_the_first_solid_card_every_detection_counts_however_faint(self):
        box = cardframe.box_of(frames(card(100), card(400, contrast=2.0), card(100)), card(100))
        self.assertEqual((box.faint, box.partial, box.worst_edge_range, box.changed), (0, False, 300.0, True))


class Detect(unittest.TestCase):
    def paper(self):
        return np.full((800, 400), float(PAPER), np.float32)

    def test_a_bright_rectangle_reads_as_its_edges_in_points_and_its_contrast(self):
        lum = self.paper()
        lum[200:520, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0, 168), Card(100.0, 260.0, 16.0, 186.0, 40.0))

    def test_a_run_shorter_than_120_pt_is_no_card(self):
        lum = self.paper()
        lum[200:438, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0, 168), None)

    def test_an_unbroken_run_taller_than_the_trees_card_is_the_card(self):
        lum = self.paper()
        lum[200:600, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0, 160), Card(100.0, 300.0, 16.0, 186.0, 40.0))

    def test_two_runs_split_by_a_gap_under_8_pt_are_one_card_and_8_pt_splits_them(self):
        lum = self.paper()
        lum[200:340, 32:372] = CARD
        lum[355:600, 32:372] = CARD
        self.assertEqual((cardframe.detect(lum, 2.0, 208).top, cardframe.detect(lum, 2.0, 208).bottom), (100.0, 300.0))
        lum[355, 32:372] = PAPER
        self.assertEqual((cardframe.detect(lum, 2.0, 208).top, cardframe.detect(lum, 2.0, 208).bottom), (178.0, 300.0))

    def test_a_brighter_neighbour_touching_the_card_across_a_1_pt_seam_is_not_joined_past_the_cards_height(self):
        lum = self.paper()
        lum[200:520, 32:372] = CARD
        lum[522:600, 32:200] = CARD + 10
        self.assertEqual(cardframe.detect(lum, 2.0, 168), Card(100.0, 260.0, 16.0, 186.0, 40.0))
        self.assertEqual(cardframe.detect(lum, 2.0, 200).bottom, 300.0, "joined while the pair fits the height")

    def test_a_run_whose_middle_row_is_paper_across_the_screen_is_no_card(self):
        lum = self.paper()
        lum[200:600, 32:372] = CARD
        lum[396:404, :] = PAPER
        self.assertIsNone(cardframe.detect(lum, 2.0, 208))

    def test_a_run_whose_middle_row_shows_one_speck_is_no_card(self):
        lum = self.paper()
        lum[200:600, 32:372] = CARD
        lum[396:404, :] = PAPER
        lum[400, 60] = 230
        self.assertIsNone(cardframe.detect(lum, 2.0, 208))

    def test_a_card_over_the_paper_column_is_invisible(self):
        lum = self.paper()
        lum[200:520, 0:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0, 168), None)
