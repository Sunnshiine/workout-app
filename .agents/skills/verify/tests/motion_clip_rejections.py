"""test_motion_clips.py mixes ClipRejections into CardFrameOnClips, so each test ID stays
CardFrameOnClips.test_*."""
from motion_support import *  # noqa: F401,F403


class ClipRejections:
    def test_an_invalid_take_is_measured_under_a_banner_reads_still_unknown_and_exits_3(self):
        code, out, _ = self.lines("ticking", load_after=63.2)
        self.assertEqual(code, 3)
        self.assertEqual(out[:3], [
            "INVALID take: load 63.2 at the end, over 50",
            "take=INVALID animations=on frames=10 window_frames=10",
            "window=start from=0.000 to=2.900 window_s=2.900",
        ])
        self.assertEqual(out[-1], "still=unknown box=still look=still")

    def test_a_take_with_animations_off_where_nothing_moved_reads_still_unknown_and_exits_3_under_a_banner(self):
        code, out, _ = self.lines("ticking", animations="off")
        self.assertEqual(code, 3)
        self.assertEqual((out[0], out[-1]), ("animations off: this take cannot show motion",
                                             "still=unknown box=still look=still"))

    def test_no_card_in_the_window_exits_1(self):
        code, out, err = self.lines("ticking", "--x", "190")
        self.assertEqual(code, 1)
        self.assertEqual(out, ["take=VALID animations=on frames=10 window_frames=10",
                               "window=start from=0.000 to=2.900 window_s=2.900"])
        self.assertEqual(err, "no card: none of the 10 frames from 0.000 s showed it\n")

    def test_a_card_that_jumps_while_faint_and_then_brightens_reads_edges_partial_and_cardstill_calls_it_invalid(self):
        video = self.clips["faint-tap"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.3, drive_end=0.4,
              card_pt=tree_frame_around(140, 300, 16, 186))
        m = cardframe.measure(video)
        box = m.card.box
        self.assertEqual((box.first_seen, box.faint, box.partial, box.worst_edge_range), (0.8, 2, True, 0.0))
        self.assertEqual(cardstill.judge_take(0, Reading.of(m)), (
            Verdict.INVALID, "the card was faint for its first 2 frames, so its edges were not read from the window's "
                             "start"))

    def test_a_run_too_narrow_to_hold_one_4_pt_cell_is_no_card_and_exits_1(self):
        code, out, err = self.lines("rule", "--x", "102")
        self.assertEqual((code, out, err), (1, ["take=VALID animations=on frames=10 window_frames=10",
                                                "window=start from=0.000 to=2.900 window_s=2.900"],
                                            "no card: none of the 10 frames from 0.000 s showed it\n"))

    def test_a_take_whose_tree_held_no_active_set_card_is_no_card_and_cardstill_calls_it_invalid(self):
        code, out, err = self.lines("ticking", card_pt="none")
        self.assertEqual((code, out, err), (1, ["take=VALID animations=on frames=10 window_frames=10",
                                                "window=start from=0.000 to=2.900 window_s=2.900"],
                                            "no card: the accessibility tree held no active-set-card when the recorder "
                                            "stopped\n"))
        self.assertEqual(self.judged("ticking", card_pt="none"), (
            Verdict.INVALID, "no card: the accessibility tree held no active-set-card when the recorder stopped"))

    def test_a_box_more_than_8_pt_from_where_the_tree_put_the_card_is_no_card_and_cardstill_calls_it_invalid(self):
        why = ("no card: the box read last, 100.0..260.0 16.0..186.0, is not where the accessibility tree put "
               "active-set-card, @12,105 178x168")
        self.assertEqual(self.lines("ticking", card_pt="@12,105 178x168")[0::2], (1, why + "\n"))
        self.assertEqual(self.judged("ticking", card_pt="@12,105 178x168"), (Verdict.INVALID, why))
        self.assertEqual(self.lines("ticking", card_pt="@20,104 178x168")[0::2], (0, ""),
                         "8 pt off in x and in y is where the tree put it")

    def test_a_card_taller_than_the_trees_card_that_shrinks_to_it_reads_its_whole_range_and_cardstill_fails_it(self):
        code, out, err = self.lines("shrink", card_pt="@16,100 170x160")
        self.assertEqual(code, 0, err)
        self.assertEqual(out[2:], [
            "first_seen=0.000 lost=0 faint=0 edges=full",
            "top=100.0..100.0 bottom=260.0..340.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=80.0",
            "contrast=40.0..40.0",
            "motion=0.083..0.083 motion_ms=0 changed_frames=1",
            "look_peak=0.0 look_frames=0",
            "still=no box=changed look=still",
        ])
        self.assertEqual(self.judged("shrink", card_pt="@16,100 170x160"), (Verdict.FAIL, "an edge moved 80.0 pt"))

    def test_cardstill_calls_a_window_with_no_card_in_any_frame_invalid(self):
        self.assertEqual(self.judged("rule"),
                         (Verdict.INVALID, "no card: none of the 10 frames from 0.000 s showed it"))

    def test_a_stamp_without_card_pt_exits_2_naming_it(self):
        video = self.dir / "untreed.mp4"
        video.write_bytes(self.clips["ticking"].read_bytes())
        stamped = stamp(video)
        stamped.write_text(stamped.read_text().replace(f"card_pt={RESTS}\n", ""))
        code, _, err = run_cardframe(video)
        self.assertEqual((code, err), (2, f"{stamped} has no card_pt=, so the card's frame in the accessibility tree "
                                          "is unknown; record it again\n"))

    def test_a_video_with_no_take_beside_it_exits_2_naming_the_stamp(self):
        video = self.dir / "unstamped.mp4"
        video.write_bytes(self.clips["still"].read_bytes())
        code, _, err = run_cardframe(video)
        self.assertEqual(code, 2)
        self.assertEqual(err, f"no take stamp {self.dir / 'unstamped.take'}; record the video with verify.sh record\n")

    def test_a_stamp_without_screen_pt_exits_2_naming_it(self):
        video = self.dir / "unscaled.mp4"
        video.write_bytes(self.clips["ticking"].read_bytes())
        stamp(video)
        stamped = video.with_suffix(".take")
        stamped.write_text(stamped.read_text().replace("screen_pt=200x400\n", ""))
        code, _, err = run_cardframe(video)
        self.assertEqual(code, 2)
        self.assertEqual(err, f"{stamped} has no screen_pt=, so its pixels cannot be read as points; record it again\n")

    def test_a_screen_whose_pixels_per_point_do_not_tile_4_pt_cells_exits_2_naming_it(self):
        video = self.dir / "odd.mp4"
        video.write_bytes(self.clips["ticking"].read_bytes())
        stamped = stamp(video)
        stamped.write_text(stamped.read_text().replace("screen_pt=200x400", "screen_pt=180x360"))
        code, _, err = run_cardframe(video)
        self.assertEqual((code, err), (2, f"{stamped}: 3.33333 px per point does not tile 4 pt cells\n"))

    def test_a_stamp_that_is_not_take_1_exits_2_naming_why(self):
        video = self.dir / "future.mp4"
        video.write_bytes(self.clips["ticking"].read_bytes())
        stamped = stamp(video)
        stamped.write_text(stamped.read_text().replace("format=take/1", "format=take/2"))
        code, _, err = run_cardframe(video)
        self.assertEqual((code, err), (2, f"{stamped}: format=take/2, not take/1\n"))

    def test_a_file_ffprobe_cannot_read_exits_70(self):
        video = self.dir / "broken.mp4"
        video.write_bytes(b"not a video")
        stamp(video, like=self.clips["still"])
        code, _, err = run_cardframe(video)
        self.assertEqual(code, 70)
        self.assertTrue(err.startswith(f"ffprobe could not read {video}"), err)
