from motion_support import *  # noqa: F401,F403
from motion_clip_rejections import ClipRejections


class CardFrameOnClips(ClipRejections, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = Path(tempfile.mkdtemp())
        cls.clips = {}
        for name, scene, seconds in [
            ("still", still, 1.0),
            ("ticking", ticks_beside, 1.0),
            ("third", a_third_of_a_point_low, 1.0),
            ("slide", slide, 2.0),
            ("cut", cuts, 2.0),
            ("drop", drops_for_three_frames, 1.5),
            ("label", swaps_a_label_inside, 1.5),
            ("shrink", shrinks_from_240_pt_to_160_pt, 1.0),
            ("rule", a_3_pt_rule_beside_a_ticking_box, 1.0),
            ("faint-tap", jumps_then_brightens_to_where_it_sits, 1.0),
            ("launch", launched(still), 1.5),
            ("launch-late", launched(still, fade_end=150), 2.6),
            ("launch-fade", launched(fades_in_place), 1.6),
            ("launch-slide", launched(slides_in_from_the_right), 1.6),
            ("launch-fly", launched(flies_in_from_the_top), 1.6),
            ("launch-jump", launched(jumps_20_pt_in_its_last_two_frames), 1.6),
            ("launch-jump-last", launched(jumps_20_pt_in_its_last_frame), 1.6),
            ("launch-zoom", zooms_from_the_icon, 1.5),
        ]:
            cls.clips[name] = cls.dir / f"{name}.mp4"
            encode(cls.clips[name], scene, seconds)
        cls.clips["lossy"] = cls.dir / "lossy.mp4"
        encode(cls.clips["lossy"], ticks_beside, 1.0, lossless=False)

    def lines(self, name, *args, **stamped):
        video = self.clips[name]
        stamp(video, **stamped)
        code, out, err = run_cardframe(video, *args)
        return code, out.splitlines(), err

    def judged(self, name, **stamped):
        result = cardstill.measured(cardstill.Filmed(name, 0, stamp(self.clips[name], **stamped)))
        return result.verdict, result.reason

    def test_a_still_card_with_nothing_else_changing_is_one_frame_an_invalid_take_and_reads_still_unknown(self):
        code, out, _ = self.lines("still")
        self.assertEqual(code, 3)
        self.assertEqual(out, [
            "INVALID take: one frame: the screen never changed while recording",
            "take=INVALID animations=on frames=1 window_frames=1",
            "window=start from=0.000 to=2.000 window_s=2.000",
            "first_seen=0.000 lost=0 faint=0 edges=full",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "look_peak=0.0 look_frames=0",
            "still=unknown box=still look=still",
        ])

    def test_a_still_card_beside_a_changing_box_reads_still(self):
        code, out, err = self.lines("ticking")
        self.assertEqual(code, 0, err)
        self.assertEqual(out, [
            "take=VALID animations=on frames=10 window_frames=10",
            "window=start from=0.000 to=2.900 window_s=2.900",
            "first_seen=0.000 lost=0 faint=0 edges=full",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "look_peak=0.0 look_frames=0",
            "still=yes box=still look=still",
        ])

    def test_edges_are_read_at_the_recordings_own_pixels_a_third_of_a_point_apart(self):
        video = self.clips["third"]
        stamp(video)
        m = cardframe.measure(video)
        box = m.card.box
        self.assertEqual((round(box.ranges["top"][0], 3), box.ranges["bottom"]), (100.333, (260.0, 260.0)))

    def test_a_still_card_in_a_lossy_recording_reads_still(self):
        code, out, err = self.lines("lossy")
        self.assertEqual(code, 0, err)
        self.assertEqual((out[0], out[-1]), ("take=VALID animations=on frames=10 window_frames=10",
                                             "still=yes box=still look=still"))

    def test_a_slide_of_160_pt_over_400_ms_reads_its_range_and_duration_by_frame_time(self):
        video = self.clips["slide"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.0, drive_end=0.5, card_pt=SLID)
        m = cardframe.measure(video)
        b = m.card.box
        self.assertEqual((m.frames, len(m.in_window)), (25, 25))
        self.assertEqual((b.first_seen, b.lost), (0.0, 0))
        self.assertEqual(b.ranges["top"], (40.0, 200.0))
        self.assertEqual(b.worst_edge_range, 160.0)
        self.assertEqual((round(b.motion[0], 3), round(b.motion[1], 3), b.motion_ms), (1.017, 1.4, 383))
        self.assertEqual(b.changed_frames, 24)
        look = m.card.look
        self.assertEqual((round(look.motion[0], 3), look.motion[1], look.ms, look.kind),
                         (1.033, 1.4, 367, LookKind.CHANGED))
        self.assertEqual(m.still, Still.NO)

    def test_a_cut_after_the_drive_is_measured_from_the_frame_showing_when_the_drive_began(self):
        video = self.clips["cut"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.3, drive_end=0.5, card_pt=SLID)
        m = cardframe.measure(video)
        self.assertEqual((m.frames, len(m.in_window), m.window.opened), (2, 2, Opened.DRIVE))
        box, look = m.card.box, m.card.look
        self.assertEqual((box.first_seen, box.worst_edge_range, box.changed_frames, m.still), (0.0, 160.0, 1, Still.NO))
        self.assertEqual((look.motion, look.kind), ((1.0, 1.0), LookKind.CUT))

    def test_the_tsv_has_a_row_per_window_frame_timed_from_the_drive(self):
        video = self.clips["slide"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.5, drive_end=0.6, card_pt=SLID)
        tsv = self.dir / "slide.tsv"
        code, _, err = run_cardframe(video, "--from", "0", "--tsv", tsv)
        self.assertEqual(code, 0, err)
        rows = tsv.read_text().splitlines()
        self.assertEqual(rows[:3], [
            "t\tt_from_drive\ttop\tbottom\tleft\tright\tcontrast\tlook\tscreen",
            "0.000\t-0.500\t40.0\t190.0\t16.0\t186.0\t40.0\t40.0\t",
            "1.017\t0.517\t46.7\t196.7\t16.0\t186.0\t40.0\t40.0\t0.115",
        ])
        self.assertEqual(len(rows), 26)

    def test_from_starts_at_the_frame_showing_then_and_rebases_the_card(self):
        video = self.clips["slide"]
        stamp(video, card_pt=SLID)
        m = cardframe.measure(video, from_s=1.19)
        self.assertEqual((m.window.opened, round(m.card.box.first_seen, 3)), (Opened.FROM, 1.183))
        self.assertEqual((round(m.card.box.ranges["top"][0], 3), m.card.box.ranges["top"][1]), (113.333, 200.0))
        self.assertEqual(len(m.in_window), 14)

    def test_a_launch_with_a_still_card_is_measured_from_the_end_of_ios_s_fade_and_reads_still(self):
        code, out, err = self.lines("launch", drive=LAUNCH_DRIVE, drive_end=1.4)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, [
            "take=VALID animations=on frames=27 window_frames=1",
            "window=ramp from=1.000 to=3.400 window_s=2.400",
            "first_seen=1.000 lost=0 faint=0 edges=full",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "look_peak=0.0 look_frames=0",
            "still=yes box=still look=still",
        ])

    def test_an_animations_off_launch_where_nothing_moved_reads_still_unknown_and_exits_3_under_a_banner(self):
        code, out, _ = self.lines("launch", drive="launch session", drive_end=1.4, animations="off")
        self.assertEqual(code, 3)
        self.assertEqual((out[0], out[1], out[-1]), ("animations off: this take cannot show motion",
                                                     "take=VALID animations=off frames=27 window_frames=1",
                                                     "still=unknown box=still look=still"))

    def test_a_card_that_fades_in_place_on_launch_reads_a_still_box_and_a_changed_look(self):
        code, out, err = self.lines("launch-fade", drive=LAUNCH_DRIVE, drive_end=1.4)
        self.assertEqual(code, 0, err)
        self.assertEqual(out[1:], [
            "window=ramp from=1.000 to=3.483 window_s=2.483",
            "first_seen=1.383 lost=0 faint=15 edges=partial",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=30.0..40.0",
            "motion=none",
            "look_peak=40.0 look_frames=24 look_motion=1.100..1.483 look_ms=383",
            "still=no box=still look=changed",
        ])

    def test_a_label_that_swaps_inside_a_still_box_is_a_cut_and_reads_still(self):
        code, out, err = self.lines("label", drive="tap --id log-active-set-button", drive_start=0.3, drive_end=0.5)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, [
            "take=VALID animations=on frames=2 window_frames=2",
            "window=drive from=0.300 to=3.000 window_s=2.700",
            "first_seen=0.000 lost=0 faint=0 edges=full",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "look_peak=1.8 look_frames=1 look_motion=1.000..1.000 look_ms=0",
            "still=yes box=still look=cut",
        ])

    def test_a_card_sliding_in_past_the_screen_edge_is_measured_from_the_fade_and_says_its_edges_are_partial(self):
        code, out, err = self.lines("launch-slide", drive=LAUNCH_DRIVE, drive_end=1.4)
        self.assertEqual(code, 0, err)
        self.assertEqual(out[1:], [
            "window=ramp from=1.000 to=3.483 window_s=2.483",
            "first_seen=1.467 lost=0 faint=0 edges=partial",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..23.7 right=186.0..193.7",
            "worst_edge_range=7.7",
            "contrast=40.0..40.0",
            "motion=1.483..1.483 motion_ms=0 changed_frames=1",
            "look_peak=40.0 look_frames=22 look_motion=1.133..1.483 look_ms=350",
            "still=no box=changed look=changed",
        ])

    def test_a_card_flying_in_from_the_top_on_launch_reads_its_flight(self):
        code, out, err = self.lines("launch-fly", drive=LAUNCH_DRIVE, drive_end=1.4)
        self.assertEqual(code, 0, err)
        self.assertEqual(out[1:], [
            "window=ramp from=1.000 to=3.483 window_s=2.483",
            "first_seen=1.000 lost=0 faint=0 edges=full",
            "top=0.0..100.0 bottom=160.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=100.0",
            "contrast=40.0..40.0",
            "motion=1.100..1.483 motion_ms=383 changed_frames=24",
            "look_peak=25.0 look_frames=24 look_motion=1.100..1.483 look_ms=383",
            "still=no box=changed look=changed",
        ])

    def test_a_20_pt_jump_in_the_last_two_frames_of_a_launch_reads_20_pt(self):
        code, out, err = self.lines("launch-jump", drive=LAUNCH_DRIVE, drive_end=1.4,
                                    card_pt=tree_frame_around(100, 280, 16, 196))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, [
            "take=VALID animations=on frames=29 window_frames=3",
            "window=ramp from=1.000 to=3.517 window_s=2.517",
            "first_seen=1.000 lost=0 faint=0 edges=full",
            "top=100.0..100.0 bottom=260.0..280.0 left=16.0..16.0 right=186.0..196.0",
            "worst_edge_range=20.0",
            "contrast=40.0..40.0",
            "motion=1.500..1.517 motion_ms=17 changed_frames=2",
            "look_peak=6.4 look_frames=2 look_motion=1.500..1.517 look_ms=17",
            "still=no box=changed look=changed",
        ])

    def test_a_20_pt_jump_in_a_launch_s_last_frame_that_brightens_x1_34_reads_edges_partial_and_still_unknown(self):
        video = self.clips["launch-jump-last"]
        stamped = stamp(video, drive=LAUNCH_DRIVE, drive_end=1.4, card_pt=tree_frame_around(100, 280, 16, 186))
        filmed = take.parse(stamped.read_text())
        found = cardframe.samples(video, filmed)
        jump = len(found) - 1
        found[jump:] = [dataclasses.replace(s, card=dataclasses.replace(s.card, contrast=s.card.contrast * 1.34))
                        for s in found[jump:]]
        m = cardframe.summarize(filmed, found)
        self.assertEqual(cardframe.report(m), [
            "take=VALID animations=on frames=28 window_frames=2",
            "window=ramp from=1.000 to=3.500 window_s=2.500",
            "first_seen=1.500 lost=0 faint=1 edges=partial",
            "top=100.0..100.0 bottom=280.0..280.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=53.6..53.6",
            "motion=none",
            "look_peak=4.4 look_frames=1 look_motion=1.500..1.500 look_ms=0",
            "still=unknown box=still look=cut",
        ])
        self.assertEqual(cardstill.judge_take(0, Reading.of(m)), (
            Verdict.INVALID, "the card was faint for its first 1 frames, so its edges were not read from the window's "
                             "start"))

    def test_a_launch_whose_fade_ended_late_and_watched_under_1_5_s_is_invalid_and_1_5_s_is_enough(self):
        code, out, _ = self.lines("launch-late", drive=LAUNCH_DRIVE, drive_end=1.4, stopped=3.9)
        self.assertEqual(code, 3)
        self.assertEqual(out[:3], [
            "INVALID take: the window watched 1.40 s from +2.500 s, under 1.5 s",
            "take=INVALID animations=on frames=27 window_frames=1",
            "window=ramp from=2.500 to=3.900 window_s=1.400",
        ])
        self.assertEqual(out[-1], "still=unknown box=still look=still")
        code, out, err = self.lines("launch-late", drive=LAUNCH_DRIVE, drive_end=1.4, stopped=4.0)
        self.assertEqual(code, 0, err)
        self.assertEqual((out[0], out[1], out[-1]), ("take=VALID animations=on frames=27 window_frames=1",
                                                     "window=ramp from=2.500 to=4.000 window_s=1.500",
                                                     "still=yes box=still look=still"))

    def test_a_launch_take_with_no_full_screen_fade_is_invalid_and_measured_from_the_drive(self):
        code, out, _ = self.lines("ticking", drive=LAUNCH_DRIVE, drive_start=0.5, drive_end=0.9)
        self.assertEqual(code, 3)
        self.assertEqual(out[:3], [
            "INVALID take: no frame after the launch began changed three quarters of the screen, so iOS's "
            "fade-in cannot be told from the app's motion",
            "take=INVALID animations=on frames=10 window_frames=5",
            "window=drive from=0.500 to=2.900 window_s=2.400",
        ])
        self.assertEqual(out[-1], "still=unknown box=still look=still")

    def test_a_launch_the_system_zooms_in_with_no_fade_reads_its_growing_card_as_still_unknown(self):
        code, out, _ = self.lines("launch-zoom", drive=LAUNCH_DRIVE, drive_start=0.05, drive_end=1.0)
        self.assertEqual(code, 3)
        self.assertEqual((out[2], out[-1]), ("window=drive from=0.050 to=3.000 window_s=2.950",
                                             "still=unknown box=changed look=changed"))

    def test_from_0_on_a_launch_reads_the_springboard_and_the_fade_as_motion(self):
        video = self.clips["launch"]
        stamp(video, drive=LAUNCH_DRIVE, drive_end=1.4)
        m = cardframe.measure(video, from_s=0)
        self.assertEqual((m.window.opened, m.card.box.first_seen, m.card.box.partial, m.card.look.kind,
                          m.still), (Opened.FROM, 0.0, False, LookKind.CHANGED, Still.NO))

    def test_three_frames_without_the_card_after_it_showed_are_lost(self):
        code, out, err = self.lines("drop")
        self.assertEqual(code, 0, err)
        self.assertEqual((out[0], out[2], out[-1]), ("take=VALID animations=on frames=5 window_frames=5",
                                                     "first_seen=0.000 lost=3 faint=0 edges=full",
                                                     "still=no box=changed look=changed"))
