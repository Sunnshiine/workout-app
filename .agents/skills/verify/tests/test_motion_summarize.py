from motion_support import *  # noqa: F401,F403


class Summarize(unittest.TestCase):

    def test_a_cut_is_one_changed_frame_of_zero_duration(self):
        m = cardframe.summarize(held_at(card(260)), [Sample(0.0, card(100), FLAT), Sample(1.0, card(260), FLAT)], 0.0)
        b = m.card.box
        self.assertEqual((b.worst_edge_range, b.motion, b.motion_ms, b.changed_frames, m.still),
                         (160.0, (1.0, 1.0), 0, 1, Still.NO))

    def test_a_move_of_half_a_point_is_not_motion_and_more_is(self):
        m = cardframe.summarize(TAKE, frames(card(100), card(100.5)), 0.0)
        self.assertEqual((m.card.box.worst_edge_range, m.card.box.motion, m.card.box.changed_frames, m.still),
                         (0.5, None, 0, Still.YES))
        m = cardframe.summarize(TAKE, frames(card(100), card(100.6)), 0.0)
        self.assertEqual((m.card.box.motion, m.card.box.changed_frames, m.still), ((0.1, 0.1), 1, Still.NO))

    def test_frames_without_the_card_before_it_shows_are_not_lost_and_after_it_are(self):
        m = cardframe.summarize(TAKE, frames(None, None, card(100), None, card(100)), 0.0)
        box = m.card.box
        self.assertEqual((box.first_seen, box.lost, box.partial, m.still), (0.2, 1, True, Still.NO))

    def test_motion_skips_a_lost_frame_and_compares_the_cards_either_side(self):
        m = cardframe.summarize(held_at(card(110)), frames(card(100), None, card(110), card(110)), 0.0)
        self.assertEqual((m.card.box.motion, m.card.box.changed_frames), ((0.2, 0.2), 1))

    def test_a_window_with_no_card_has_no_box_and_its_stillness_is_unknown(self):
        m = cardframe.summarize(TAKE, [Sample(0.0, None, FLAT), Sample(1.0, None, FLAT)], 0.5)
        self.assertEqual((len(m.in_window), m.card, m.still),
                         (2, cardframe.NoCard("none of the 2 frames from 0.500 s showed it"), Still.UNKNOWN))

    def test_the_frame_showing_at_from_opens_the_window(self):
        m = cardframe.summarize(held_at(card(120)), [Sample(0.0, card(100), FLAT), Sample(0.4, card(120), FLAT),
                                                     Sample(1.0, None, FLAT)], 0.5)
        self.assertEqual((len(m.in_window), m.card.box.first_seen, m.card.box.lost, m.card.box.ranges["top"]),
                         (2, 0.4, 1, (120.0, 120.0)))

    def test_a_move_still_running_when_the_recorder_stopped_reads_still_no_though_the_tree_put_the_card_ahead(self):
        moving = frames(card(100), card(110), card(120), card(130))
        m = cardframe.summarize(held_at(card(160)), moving, 0.0)
        self.assertEqual((m.card.box.motion, m.card.box.worst_edge_range, m.still), ((0.1, 0.3), 30.0, Still.NO))

    def test_a_box_still_moving_at_the_stop_is_the_card_only_at_the_tree_card_s_height_and_horizontal_middle(self):
        short = frames(card(100, 200), card(110, 210), card(120, 220), card(130, 230))
        self.assertEqual(cardframe.summarize(held_at(card(160)), short, 0.0).card, cardframe.NoCard(
            "the box read last, 130.0..230.0 16.0..186.0, is not where the accessibility tree put active-set-card, "
            "@16,160 170x160"))
        aside = frames(*(card(top, left=116.0, right=286.0) for top in (100, 110, 120, 130)))
        self.assertIsInstance(cardframe.summarize(held_at(card(160)), aside, 0.0).card, cardframe.NoCard)

    def test_a_148_pt_box_on_the_middle_of_a_308_pt_tree_card_is_no_card(self):
        m = cardframe.summarize(held_at(card(100, 408)), frames(card(180, 328), card(180, 328)), 0.0)
        self.assertEqual(m.card, cardframe.NoCard("the box read last, 180.0..328.0 16.0..186.0, is not where the "
                                                  "accessibility tree put active-set-card, @16,100 170x308"))

    def test_a_box_more_than_24_pt_shorter_than_the_tree_card_on_its_middle_is_no_card(self):
        def read(top, bottom):
            return cardframe.summarize(TAKE, frames(card(top, bottom), card(top, bottom)), 0.0).card
        self.assertEqual(read(130, 230), cardframe.NoCard(
            "the box read last, 130.0..230.0 16.0..186.0, is not where the accessibility tree put active-set-card, "
            "@16,100 170x160"))
        self.assertIsInstance(read(112, 248), cardframe.Seen, "24 pt shorter is the card")
        self.assertIsInstance(read(112.1, 247.9), cardframe.NoCard)

    def test_a_slide_after_the_fade_from_black_then_a_full_screen_dim_is_invalid_and_never_still_yes(self):
        m = cardframe.summarize(held_at(card(300), LAUNCH), launch_frames(dim=True))
        self.assertEqual(([r.rule for r in m.invalid], m.card.box.worst_edge_range, m.still),
                         (["screen"], 200.0, Still.UNKNOWN))
        m = cardframe.summarize(held_at(card(300), LAUNCH), launch_frames())
        self.assertEqual((m.window.at, m.invalid, m.card.box.worst_edge_range, m.still), (1.0, (), 200.0, Still.NO))

    def test_a_fade_with_a_near_repeat_and_an_app_frame_mid_fade_opens_at_its_last_full_screen_frame(self):
        app_frame = lum(80)
        app_frame[:68] = 100
        near_repeat = lum(120)
        near_repeat[:4, :12] += 1.0
        fade = [Sample(0.8, None, lum(40)), Sample(0.85, None, lum(80)), Sample(0.88, None, app_frame),
                Sample(0.9, None, lum(120)), Sample(0.93, None, near_repeat), Sample(0.95, card(100), lum(160)),
                Sample(1.0, card(100), FLAT)]
        self.assertEqual([round(c, 2) for c in cardframe.screen_changes(fade)[1:]], [1.0, 0.71, 1.0, 0.01, 1.0, 1.0])
        m = cardframe.summarize(held_at(card(100), LAUNCH), launch_frames()[:7] + fade)
        self.assertEqual((m.window, m.invalid, m.still), (Window(Opened.RAMP, 13, 1.0, 3.0), (), Still.YES))

    def test_a_still_card_then_a_full_screen_dim_after_the_fade_with_no_partial_frame_between_is_invalid(self):
        dim = [Sample(1.3, card(100), FLAT)] + [Sample(round(1.6 + 0.02 * k, 3), card(100), FLAT * (1 - 0.05 * k))
                                                for k in range(1, 5)]
        m = cardframe.summarize(held_at(card(100), LAUNCH), launch_frames()[:13] + dim)
        self.assertEqual(([r.rule for r in m.invalid], m.window.at, m.still), (["screen"], 1.0, Still.UNKNOWN))

    def test_a_20_pt_layout_jump_in_the_last_two_frames_of_a_launch_reads_20_pt(self):
        settled = Card(top=470, bottom=820, left=16, right=386, contrast=15)
        jumped = Card(top=470, bottom=840, left=16, right=396, contrast=15)
        screen = np.full((218, 100), float(PAPER), np.float32)
        found = ([Sample(0.0, None, screen * 0), Sample(0.4, settled, screen)]
                 + [Sample(round(0.5 + 0.1 * k, 3), settled, screen) for k in range(8)]
                 + [Sample(2.0, jumped, screen), Sample(2.02, jumped, screen)])
        m = cardframe.summarize(held_at(jumped, LAUNCH), found)
        self.assertEqual(m.window, Window(Opened.RAMP, 1, 0.4, 3.6))
        self.assertEqual((m.card.box.worst_edge_range, m.card.box.motion, m.still), (20.0, (2.0, 2.0), Still.NO))


def ruled(m, *rules, animations="on"):
    return dataclasses.replace(m, take=dataclasses.replace(m.take, animations=animations),
                               invalid=tuple(Reason(rule, f"{rule} reason") for rule in rules))


class StillOf(unittest.TestCase):
    def test_only_rules_that_hide_motion_and_never_invent_it_keep_a_move_sound(self):
        self.assertEqual([cardframe.moved_counts(rules) for rules in
                          [(), ("load",), ("window",), ("load", "window"), ("ramp",), ("load", "coverage"),
                           ("recorder_exit",), ("recorder_early",)]],
                         [True, True, True, True, False, False, False, False])

    def test_a_reading_that_cannot_vouch_says_why_by_its_edges_then_its_rules_then_its_animations(self):
        held = cardframe.summarize(TAKE, frames(card(100), card(100)), 0.0)
        faint = cardframe.summarize(TAKE, frames(card(100, contrast=5.0), card(100)), 0.0)
        missing = cardframe.summarize(TAKE, frames(None, card(100)), 0.0)
        empty = cardframe.summarize(TAKE, [Sample(0.0, None, FLAT)], 0.0)
        self.assertEqual([m.unvouched for m in [ruled(held), ruled(held, "load"), ruled(held, animations="off"),
                                                ruled(faint, "load", animations="off"), ruled(missing),
                                                ruled(empty, "load")]], [
            None,
            "take INVALID: load reason",
            "animations off",
            "the card was faint for its first 1 frames, so its edges were not read from the window's start",
            "the card was missing from the window's first frames, so its edges were not read from the window's start",
            "take INVALID: load reason",
        ])

    def test_the_still_table(self):
        moved = cardframe.summarize(held_at(card(110)), frames(card(100), card(110)), 0.0)
        faded = cardframe.summarize(TAKE, looks(200, 210, 220, 230, 240, 240), 0.0)
        held = cardframe.summarize(TAKE, frames(card(100), card(100)), 0.0)
        held_after_a_faint_frame = cardframe.summarize(TAKE, frames(card(100, contrast=5.0), card(100)), 0.0)
        empty = cardframe.summarize(TAKE, [Sample(0.0, None, FLAT)], 0.0)
        cases = [
            ("box moved, VALID", ruled(moved), Still.NO),
            ("look changed, VALID", ruled(faded), Still.NO),
            ("box moved under load", ruled(moved, "load"), Still.NO),
            ("box moved in a short window", ruled(moved, "window"), Still.NO),
            ("box moved, animations off", ruled(moved, animations="off"), Still.NO),
            ("box moved with no ramp", ruled(moved, "ramp"), Still.UNKNOWN),
            ("look changed with no ramp", ruled(faded, "ramp"), Still.UNKNOWN),
            ("box moved under load and no coverage", ruled(moved, "load", "coverage"), Still.UNKNOWN),
            ("box moved, recorder exit 1", ruled(moved, "recorder_exit"), Still.UNKNOWN),
            ("nothing moved, VALID", ruled(held), Still.YES),
            ("nothing moved, VALID, edges partial", ruled(held_after_a_faint_frame), Still.UNKNOWN),
            ("nothing moved under load", ruled(held, "load"), Still.UNKNOWN),
            ("nothing moved, animations off", ruled(held, animations="off"), Still.UNKNOWN),
            ("nothing moved, animations unknown", ruled(held, animations="unknown"), Still.UNKNOWN),
            ("no card", ruled(empty), Still.UNKNOWN),
        ]
        for name, m, expected in cases:
            with self.subTest(name):
                self.assertEqual(m.still, expected)
