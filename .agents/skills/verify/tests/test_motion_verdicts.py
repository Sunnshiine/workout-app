from motion_support import *  # noqa: F401,F403


def reading(rules=(), invalid="", animations="on", no_card=None, lost=0, faint=0, partial=False, worst=0.0,
            look="still"):
    first = [card(100, contrast=5.0)] * faint + ([None] if partial and not faint else [])
    m = cardframe.summarize(dataclasses.replace(TAKE, animations=animations), frames(*first, card(100)), 0.0)
    m = dataclasses.replace(m, invalid=(Reason(",".join(rules), invalid),) if rules else ())
    return dataclasses.replace(Reading.of(m), rules=rules, no_card=no_card, lost=lost, worst_edge_range=worst,
                               look=look, frames=37, load="12.31/14.02")


LOAD = "load 63.2 at the end, over 50"
RECORDER = "recorder exit 1 after SIGINT; the video may be cut short"
EARLY = "the recorder stopped before the take ended"
UNCOVERED = "the screen never changed after the drive began at +3.50 s, so the take shows nothing the drive did"
SHORT = "the window watched 0.90 s from +2.500 s, under 1.5 s"
NO_FRAMES = "none of the 37 frames from 0.000 s showed it"
NO_FADE = ("no frame after the launch began changed three quarters of the screen, so iOS's fade-in cannot be told "
           "from the app's motion")


PASSES = [Verdict.PASS] * 8


class RestEnd(unittest.TestCase):
    def test_the_rest_end_take_starts_26_s_after_the_superset_log_tap_returned(self):
        switch = dataclasses.replace(TAKE, started=1791817306.217, drive_end=2.454)
        self.assertEqual(round(cardstill.rest_end_at(switch), 3), 1791817334.671)

    def test_it_is_late_only_when_its_stamp_started_more_than_2_s_after_that(self):
        target = 1791817334.671
        for started, late in [(1791817335.900, 0.0), (1791817336.671, 0.0), (1791817336.771, 2.1)]:
            with self.subTest(started=started):
                rest_end = dataclasses.replace(TAKE, started=started)
                self.assertEqual(round(cardstill.late_by(target, rest_end), 3), late)


class JudgeTake(unittest.TestCase):
    def test_the_truth_table(self):
        cases = [
            (75, reading(), 0.0, (Verdict.INVALID, "record exited 75")),
            (1, None, 0.0, (Verdict.INVALID, "record exited 1")),
            (0, None, 0.0, (Verdict.INVALID, "record left no stamp")),
            (3, reading(rules=("load",), invalid=LOAD), 0.0, (Verdict.INVALID, f"take INVALID: {LOAD}")),
            (3, reading(rules=("load",), invalid=LOAD, no_card=NO_FRAMES), 0.0,
             (Verdict.INVALID, f"take INVALID: {LOAD}")),
            (3, reading(rules=("load",), invalid=LOAD, worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (3, reading(rules=("load",), invalid=LOAD, lost=2), 0.0, (Verdict.FAIL, "lost the card in 2 frames")),
            (3, reading(rules=("recorder_exit",), invalid=RECORDER, worst=412.0), 0.0,
             (Verdict.INVALID, f"take INVALID: {RECORDER}")),
            (3, reading(rules=("recorder_early",), invalid=EARLY, lost=2), 0.0,
             (Verdict.INVALID, f"take INVALID: {EARLY}")),
            (3, reading(rules=("coverage",), invalid=UNCOVERED, worst=412.0), 0.0,
             (Verdict.INVALID, f"take INVALID: {UNCOVERED}")),
            (3, reading(rules=("load", "coverage"), invalid=f"{LOAD}; {UNCOVERED}", lost=2), 0.0,
             (Verdict.INVALID, f"take INVALID: {LOAD}; {UNCOVERED}")),
            (3, reading(rules=("window",), invalid=SHORT, worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (3, reading(rules=("window",), invalid=SHORT), 0.0, (Verdict.INVALID, f"take INVALID: {SHORT}")),
            (3, reading(rules=("ramp",), invalid=NO_FADE, worst=412.0), 0.0,
             (Verdict.INVALID, f"take INVALID: {NO_FADE}")),
            (0, reading(animations="off", worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(animations="off"), 0.0, (Verdict.INVALID, "animations off")),
            (0, reading(animations="off", lost=2), 0.0, (Verdict.FAIL, "lost the card in 2 frames")),
            (0, reading(), 3.4, (Verdict.INVALID, "started 3.4 s late")),
            (0, reading(worst=412.0), 3.4, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(no_card=NO_FRAMES), 0.0, (Verdict.INVALID, f"no card: {NO_FRAMES}")),
            (0, reading(faint=2, partial=True), 0.0,
             (Verdict.INVALID, "the card was faint for its first 2 frames, so its edges were not read from the "
                               "window's start")),
            (0, reading(partial=True), 0.0,
             (Verdict.INVALID, "the card was missing from the window's first frames, so its edges were not read "
                               "from the window's start")),
            (0, reading(faint=2, partial=True, worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(partial=True, lost=2), 0.0, (Verdict.FAIL, "lost the card in 2 frames")),
            (3, reading(rules=("load",), invalid=LOAD, faint=2, partial=True), 0.0,
             (Verdict.INVALID, "the card was faint for its first 2 frames, so its edges were not read from the "
                               "window's start")),
            (3, reading(no_card=NO_FRAMES), 0.0, (Verdict.INVALID, f"no card: {NO_FRAMES}")),
            (0, reading(lost=27), 0.0, (Verdict.FAIL, "lost the card in 27 frames")),
            (0, reading(worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(worst=0.6), 0.0, (Verdict.FAIL, "an edge moved 0.6 pt")),
            (0, reading(worst=0.5), 0.0, (Verdict.PASS, "")),
            (3, reading(), 0.0, (Verdict.PASS, "")),
        ]
        for record_exit, r, late, expected in cases:
            with self.subTest(record_exit=record_exit, reading=r, late=late):
                self.assertEqual(cardstill.judge_take(record_exit, r, late), expected)

    def test_a_take_that_did_not_land_is_invalid_even_when_its_card_moved(self):
        missed = 'the take ended without "Set 3 of 3"'
        cases = [
            (0, reading(), (Verdict.INVALID, missed)),
            (3, reading(rules=("load",), invalid=LOAD), (Verdict.INVALID, missed)),
            (0, reading(no_card=NO_FRAMES), (Verdict.INVALID, missed)),
            (0, reading(worst=412.0), (Verdict.INVALID, missed)),
            (0, reading(lost=2), (Verdict.INVALID, missed)),
            (75, reading(), (Verdict.INVALID, "record exited 75")),
        ]
        for record_exit, r, expected in cases:
            with self.subTest(record_exit=record_exit, reading=r):
                self.assertEqual(cardstill.judge_take(record_exit, r, 0.0, missed), expected)


class LaneVerdict(unittest.TestCase):
    def test_a_head_fail_fails_the_lane_even_beside_invalid_takes(self):
        control = results(*[Verdict.INVALID] * 8)
        head = results(Verdict.PASS, Verdict.FAIL, *[Verdict.INVALID] * 6)
        self.assertEqual(cardstill.lane_verdict("ea5af074", control, head),
                         (Verdict.FAIL, "head node-tap: fail reason"))

    def test_any_invalid_take_on_either_side_makes_the_lane_invalid(self):
        control = results(Verdict.FAIL, *[Verdict.PASS] * 6, Verdict.INVALID)
        self.assertEqual(cardstill.lane_verdict("ea5af074", control, results(*PASSES)),
                         (Verdict.INVALID, "control superset-rest-end: invalid reason"))

    def test_a_control_that_never_failed_makes_the_lane_invalid(self):
        self.assertEqual(cardstill.lane_verdict("ea5af074", results(*PASSES), results(*PASSES)), (
            Verdict.INVALID,
            "the control ea5af074 held the card still on every take, so this host or this metric cannot see "
            "motion now",
        ))

    def test_a_control_whose_only_miss_is_no_card_in_any_frame_makes_the_lane_invalid(self):
        def judged(readings):
            return [TakeResult(spec.name, *cardstill.judge_take(0, r), r) for spec, r in zip(cardstill.TAKES, readings)]

        control = judged([reading(no_card=NO_FRAMES)] + [reading()] * 7)
        self.assertEqual(cardstill.lane_verdict("ea5af074", control, judged([reading()] * 8)),
                         (Verdict.INVALID, f"control single-log-rest-start: no card: {NO_FRAMES}"))

    def test_a_still_head_over_a_control_that_moved_passes(self):
        control = results(Verdict.FAIL, Verdict.PASS, Verdict.FAIL, *[Verdict.PASS] * 5)
        self.assertEqual(cardstill.lane_verdict("ea5af074", control, results(*PASSES)), (
            Verdict.PASS, "the head held the card still on every take; the control ea5af074 moved it on 2"))

    def test_the_verdicts_exit_0_1_3(self):
        self.assertEqual(cardstill.EXIT, {Verdict.PASS: 0, Verdict.FAIL: 1, Verdict.INVALID: 3})


class ReadingOf(unittest.TestCase):
    def test_a_label_swapped_inside_a_still_box_reads_cut_in_the_table_and_passes(self):
        r = Reading.of(cardframe.summarize(TAKE, looks(230, 230, 240, 240)))
        self.assertEqual((r.look, r.worst_edge_range, cardstill.judge_take(0, r)), ("cut", 0.0, (Verdict.PASS, "")))

    def test_a_fade_inside_a_still_box_reads_its_duration_in_the_table_and_passes(self):
        r = Reading.of(cardframe.summarize(TAKE, looks(200, 210, 220, 230, 240, 240)))
        self.assertEqual((r.look, cardstill.judge_take(0, r)), ("changed 300 ms", (Verdict.PASS, "")))


class Table(unittest.TestCase):
    def test_a_row_sets_control_and_head_side_by_side(self):
        control = [TakeResult("node-tap", Verdict.FAIL, "an edge moved 412.0 pt",
                              reading(worst=412.0, look="changed 650 ms"))]
        head = [TakeResult("node-tap", Verdict.INVALID, "record exited 75")]
        rows = cardstill.table(control, head)
        self.assertEqual(rows[0], [
            "take",
            "control_verdict", "control_worst_edge", "control_lost", "control_look", "control_frames",
            "control_load", "control_reason",
            "head_verdict", "head_worst_edge", "head_lost", "head_look", "head_frames", "head_load", "head_reason",
        ])
        self.assertEqual(rows[2], [
            "node-tap",
            "FAIL", "412.0", "0", "changed 650 ms", "37", "12.31/14.02", "an edge moved 412.0 pt",
            "INVALID", "", "", "", "", "", "record exited 75",
        ])
        self.assertEqual(len(rows), 9)
