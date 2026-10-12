#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""uv run .agents/skills/verify/tests/test_motion.py      (needs ffmpeg and ffprobe on PATH)"""
import contextlib
import dataclasses
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

SKILL = Path(__file__).resolve().parent.parent
MOTION = SKILL / "motion"
sys.path.insert(0, str(SKILL))
sys.path.insert(0, str(MOTION))
import cardframe  # noqa: E402
import take  # noqa: E402
import cardstill  # noqa: E402
from cardframe import Card, Sample  # noqa: E402
from cardstill import Reading, TakeResult, Verdict  # noqa: E402

SCREEN_PT = (200, 400)
VIDEO_PX_PER_PT = 3
PAPER = 200
CARD = 240
FPS = 60
STILL_BOX = (100, 260, 16, 186)


def scene_frames(scene, seconds):
    w, h = (n * VIDEO_PX_PER_PT for n in SCREEN_PT)
    for i in range(round(seconds * FPS)):
        paper, boxes = scene(i)
        img = np.full((h, w), paper, np.uint8)
        for box in boxes:
            top, bottom, left, right = box[:4]
            s = VIDEO_PX_PER_PT
            img[round(top * s):round(bottom * s), round(left * s):round(right * s)] = box[4] if len(box) > 4 else CARD
        yield img


def encode(path, scene, seconds, lossless=True):
    """Keeps only the frames that changed, each at its own time, as simctl's recordVideo does. RGB, because
    ffmpeg versions convert YUV back to RGB a unit apart, and the literals here are exact."""
    w, h = (n * VIDEO_PX_PER_PT for n in SCREEN_PT)
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray", "-s", f"{w}x{h}",
         "-framerate", str(FPS), "-i", "-", "-vf", "mpdecimate=hi=1:lo=1:frac=0", "-fps_mode", "vfr",
         "-c:v", "libx264rgb", *(["-qp", "0"] if lossless else []), "-pix_fmt", "rgb24", str(path)],
        stdin=subprocess.PIPE,
    )
    for img in scene_frames(scene, seconds):
        proc.stdin.write(img.tobytes())
    proc.stdin.close()
    assert proc.wait() == 0, f"ffmpeg could not encode {path}"


def stamp(video, drive="", drive_start=0.0, drive_end=0.0, load_after=14.02, animations="on", like=None):
    pts, size = take.probe(like or video)
    filmed = take.Take(
        name=video.stem, video=video.name, drive=drive, tail=2.0, load_limit=50.0, load_before=12.31,
        load_after=load_after, started=1791817306.217, drive_start=drive_start, drive_end=drive_end,
        stopped=round(max(pts[-1], drive_end) + 2.0, 3), recorder_exit=0, recorder_early=False, frames=len(pts),
        first_frame=round(pts[0], 3), last_frame=round(pts[-1], 3), video_px=size)
    path = video.with_suffix(".take")
    path.write_text("\n".join(take.take_lines(filmed) + [
        f"screen_pt={SCREEN_PT[0]}x{SCREEN_PT[1]}",
        f"animations={animations}",
        "app=app 804e750cad00 commit ea5af074 (this worktree's build)",
    ]) + "\n")
    return path


def still(i):
    return PAPER, [STILL_BOX]


def a_third_of_a_point_low(i):
    return PAPER, [(100 + 1 / 3, 260, 16, 186)]


def ticks_beside(i):
    return PAPER, [STILL_BOX, (300, 320, 100, 150, PAPER + 10 + 4 * (i // 6))]


def slide(i):
    t = i / FPS
    progress = min(max((t - 1.0) / 0.4, 0.0), 1.0)
    top = 40 + 160 * progress
    return PAPER, [(top, top + 150, 16, 186)]


def cuts(i):
    top = 40 if i < FPS else 200
    return PAPER, [(top, top + 150, 16, 186)]


def zoomed(box, scale):
    top, bottom, left, right = box
    cy, cx, h, w = (top + bottom) / 2, (left + right) / 2, (bottom - top) * scale, (right - left) * scale
    return (cy - h / 2, cy + h / 2, cx - w / 2, cx + w / 2)


def fades_in(i):
    if i < FPS:
        return 10 + 3 * i, []
    k = min((i - FPS + 1) / 10, 1.0)
    return round(PAPER * k), [STILL_BOX + (round(CARD * k),)]


def launches(slide_after=0.0):
    def scene(i):
        if i < 18:
            return PAPER, [(100, 300, 12, 196)]
        if i < FPS:
            return 10 + 3 * i, []
        if i < FPS + 6:
            return PAPER, [zoomed(STILL_BOX, 0.8 + 0.2 * (i - FPS) / 6)]
        progress = min((i - FPS - 6) / 18, 1.0)
        top, bottom, left, right = STILL_BOX
        lift = slide_after * (1 - progress)
        return PAPER, [(top + lift, bottom + lift, left, right)]
    return scene


def drops_for_three_frames(i):
    return (PAPER + 3 * (i - FPS + 1), []) if FPS <= i < FPS + 3 else (PAPER, [STILL_BOX])


def run_cardframe(*args):
    done = subprocess.run(
        [sys.executable, str(MOTION / "cardframe.py"), *map(str, args)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr




class CardFrameOnClips(unittest.TestCase):
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
            ("launch", launches(), 1.5),
            ("launch-slide", launches(slide_after=40), 1.5),
            ("launch-fade", fades_in, 1.5),
            ("drop", drops_for_three_frames, 1.5),
        ]:
            cls.clips[name] = cls.dir / f"{name}.mp4"
            encode(cls.clips[name], scene, seconds)
        cls.clips["lossy"] = cls.dir / "lossy.mp4"
        encode(cls.clips["lossy"], ticks_beside, 1.0, lossless=False)

    def test_a_still_card_with_nothing_else_changing_is_one_frame_an_invalid_take_and_reads_still(self):
        video = self.clips["still"]
        stamp(video)
        code, out, _ = run_cardframe(video)
        self.assertEqual(code, 3)
        self.assertEqual(out.splitlines(), [
            "INVALID take: one frame: the screen never changed while recording",
            "take=INVALID animations=on frames=1 window_frames=1",
            "first_seen=0.000 lost=0",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "still=yes",
        ])

    def test_a_still_card_beside_a_changing_box_reads_still(self):
        video = self.clips["ticking"]
        stamp(video)
        code, out, err = run_cardframe(video)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines(), [
            "take=VALID animations=on frames=10 window_frames=10",
            "first_seen=0.000 lost=0",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "still=yes",
        ])

    def test_edges_are_read_at_the_recordings_own_pixels_a_third_of_a_point_apart(self):
        video = self.clips["third"]
        stamp(video)
        m = cardframe.measure(video)
        self.assertEqual((round(m.ranges["top"][0], 3), m.ranges["bottom"]), (100.333, (260.0, 260.0)))

    def test_a_still_card_in_a_lossy_recording_reads_still(self):
        video = self.clips["lossy"]
        stamp(video)
        code, out, err = run_cardframe(video)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[0], "take=VALID animations=on frames=10 window_frames=10")
        self.assertEqual(out.splitlines()[-1], "still=yes")

    def test_a_slide_of_160_pt_over_400_ms_reads_its_range_and_duration_by_frame_time(self):
        video = self.clips["slide"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.0, drive_end=0.5)
        m = cardframe.measure(video)
        self.assertEqual((m.frames, len(m.window)), (25, 25))
        self.assertEqual((m.first_seen, m.lost), (0.0, 0))
        self.assertEqual(m.ranges["top"], (40.0, 200.0))
        self.assertEqual(m.worst_edge_range, 160.0)
        self.assertEqual((round(m.motion[0], 3), round(m.motion[1], 3), m.motion_ms), (1.017, 1.4, 383))
        self.assertEqual(m.changed_frames, 24)
        self.assertEqual(m.still, False)

    def test_a_cut_after_the_drive_is_measured_from_the_frame_showing_when_the_drive_began(self):
        video = self.clips["cut"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.3, drive_end=0.5)
        m = cardframe.measure(video)
        self.assertEqual((m.frames, len(m.window)), (2, 2))
        self.assertEqual((m.first_seen, m.worst_edge_range, m.changed_frames, m.still), (0.0, 160.0, 1, False))

    def test_the_tsv_has_a_row_per_window_frame_timed_from_the_drive(self):
        video = self.clips["slide"]
        stamp(video, drive="tap --id log-active-set-button", drive_start=0.5, drive_end=0.6)
        tsv = self.dir / "slide.tsv"
        code, _, err = run_cardframe(video, "--from", "0", "--tsv", tsv)
        self.assertEqual(code, 0, err)
        rows = tsv.read_text().splitlines()
        self.assertEqual(rows[:3], [
            "t\tt_from_drive\ttop\tbottom\tleft\tright\tcontrast",
            "0.000\t-0.500\t40.0\t190.0\t16.0\t186.0\t40.0",
            "1.017\t0.517\t46.7\t196.7\t16.0\t186.0\t40.0",
        ])
        self.assertEqual(len(rows), 26)

    def test_from_starts_at_the_frame_showing_then_and_rebases_the_card(self):
        video = self.clips["slide"]
        stamp(video)
        m = cardframe.measure(video, from_s=1.19)
        self.assertEqual(round(m.first_seen, 3), 1.183)
        self.assertEqual((round(m.ranges["top"][0], 3), m.ranges["top"][1]), (113.333, 200.0))
        self.assertEqual(len(m.window), 14)

    def test_a_launch_is_measured_from_the_card_at_full_width_so_the_system_zoom_reads_still(self):
        video = self.clips["launch"]
        stamp(video, drive="launch --animated session", drive_start=0.0, drive_end=1.4)
        m = cardframe.measure(video)
        self.assertEqual((round(m.first_seen, 3), m.lost, m.worst_edge_range, m.still), (1.1, 0, 0.0, True))

    def test_a_launch_that_fades_in_is_measured_once_the_card_nears_the_median_contrast_of_its_last_frames(self):
        video = self.clips["launch-fade"]
        stamp(video, drive="launch session", drive_start=0.0, drive_end=1.4, animations="off")
        m = cardframe.measure(video)
        self.assertEqual((round(m.first_seen, 3), m.worst_edge_range, m.still), (1.083, 0.0, True))

    def test_a_card_that_slides_in_after_the_launch_zoom_reads_its_slide(self):
        video = self.clips["launch-slide"]
        stamp(video, drive="launch --animated session", drive_start=0.0, drive_end=1.4)
        m = cardframe.measure(video)
        self.assertEqual((round(m.first_seen, 3), m.lost, m.ranges["top"], m.still), (1.1, 0, (100.0, 140.0), False))
        self.assertEqual((round(m.motion[0], 3), round(m.motion[1], 3)), (1.117, 1.4))

    def test_from_0_on_a_launch_reads_the_springboard_and_the_zoom_as_motion(self):
        video = self.clips["launch"]
        stamp(video, drive="launch --animated session", drive_start=0.0, drive_end=1.4)
        m = cardframe.measure(video, from_s=0)
        self.assertEqual((m.first_seen, m.still), (0.0, False))

    def test_three_frames_without_the_card_after_it_showed_are_lost(self):
        video = self.clips["drop"]
        stamp(video)
        code, out, err = run_cardframe(video)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[:2], ["take=VALID animations=on frames=5 window_frames=5",
                                                "first_seen=0.000 lost=3"])
        self.assertEqual(out.splitlines()[-1], "still=no")

    def test_an_invalid_take_is_measured_under_a_banner_and_exits_3(self):
        video = self.clips["ticking"]
        stamp(video, load_after=63.2)
        code, out, _ = run_cardframe(video)
        self.assertEqual(code, 3)
        self.assertEqual(out.splitlines()[:3], [
            "INVALID take: load 63.2 at the end, at or over 50",
            "take=INVALID animations=on frames=10 window_frames=10",
            "first_seen=0.000 lost=0",
        ])

    def test_a_take_with_animations_off_exits_3_under_a_banner(self):
        video = self.clips["ticking"]
        stamp(video, animations="off")
        code, out, _ = run_cardframe(video)
        self.assertEqual(code, 3)
        self.assertEqual(out.splitlines()[0], "animations off: this take cannot show motion")
        self.assertEqual(out.splitlines()[-1], "still=yes")

    def test_no_card_in_the_window_exits_1(self):
        video = self.clips["ticking"]
        stamp(video)
        code, out, err = run_cardframe(video, "--x", "190")
        self.assertEqual(code, 1)
        self.assertEqual(out, "take=VALID animations=on frames=10 window_frames=10\n")
        self.assertEqual(err, "no card in any of the 10 frames from 0.000 s\n")

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


def card(top, bottom=None, left=16.0, right=186.0, contrast=40.0):
    return Card(top, top + 160 if bottom is None else bottom, left, right, contrast)


TAKE = take.Take(
    name="x", video="x.mp4", drive="", tail=2.0, load_limit=50.0, load_before=1.0, load_after=1.0, started=0.0,
    drive_start=0.0, drive_end=0.0, stopped=3.0, recorder_exit=0, recorder_early=False, frames=2, first_frame=0.0,
    last_frame=1.0, video_px=(600, 1200), screen_pt=(200, 400), animations="on")


class Summarize(unittest.TestCase):

    def test_a_cut_is_one_changed_frame_of_zero_duration(self):
        m = cardframe.summarize(TAKE, [Sample(0.0, card(100)), Sample(1.0, card(260))], 0.0)
        self.assertEqual((m.worst_edge_range, m.motion, m.motion_ms, m.changed_frames, m.still),
                         (160.0, (1.0, 1.0), 0, 1, False))

    def test_a_move_under_three_quarters_of_a_point_is_not_motion_but_counts_against_still(self):
        m = cardframe.summarize(TAKE, [Sample(0.0, card(100)), Sample(0.5, card(100.5))], 0.0)
        self.assertEqual((m.worst_edge_range, m.motion, m.changed_frames, m.still), (0.5, None, 0, True))
        m = cardframe.summarize(TAKE, [Sample(0.0, card(100)), Sample(0.5, card(100.6))], 0.0)
        self.assertEqual(m.still, False)

    def test_frames_without_the_card_before_it_shows_are_not_lost_and_after_it_are(self):
        samples = [Sample(0.0, None), Sample(0.1, None), Sample(0.2, card(100)), Sample(0.3, None),
                   Sample(0.4, card(100))]
        m = cardframe.summarize(TAKE, samples, 0.0)
        self.assertEqual((m.first_seen, m.lost, m.still), (0.2, 1, False))

    def test_motion_skips_a_lost_frame_and_compares_the_cards_either_side(self):
        samples = [Sample(0.0, card(100)), Sample(0.1, None), Sample(0.2, card(110)), Sample(0.3, card(110))]
        m = cardframe.summarize(TAKE, samples, 0.0)
        self.assertEqual((m.motion, m.changed_frames), ((0.2, 0.2), 1))

    def test_a_window_with_no_card_has_no_first_seen_and_is_not_still(self):
        m = cardframe.summarize(TAKE, [Sample(0.0, None), Sample(1.0, None)], 0.5)
        self.assertEqual((len(m.window), m.first_seen, m.lost, m.still), (2, None, 0, False))

    def test_the_frame_showing_at_from_opens_the_window(self):
        m = cardframe.summarize(TAKE, [Sample(0.0, card(100)), Sample(0.4, card(120)), Sample(1.0, None)], 0.5)
        self.assertEqual((len(m.window), m.first_seen, m.lost, m.ranges["top"]), (2, 0.4, 1, (120.0, 120.0)))


class FullSize(unittest.TestCase):
    def launch(self, last_right):
        zoom = [Sample(1.0, card(110, left=40.0, right=162.0)), Sample(1.017, card(105, left=28.0, right=174.0))]
        settled = [Sample(round(1.033 + 0.017 * k, 3), card(100)) for k in range(8)]
        return zoom + settled + [Sample(1.2, card(100, right=last_right))]

    def test_the_window_opens_after_the_last_two_unsettled_frames_in_a_row(self):
        self.assertEqual(cardframe.launch_settled_at(self.launch(186.0), 0.0), 1.033)

    def test_one_stray_last_frame_keeps_the_window_and_counts_against_still(self):
        found = self.launch(187.0)
        from_s = cardframe.launch_settled_at(found, 0.0)
        m = cardframe.summarize(TAKE, found, from_s)
        self.assertEqual((from_s, len(m.window), m.worst_edge_range, m.still), (1.033, 9, 1.0, False))

    def test_one_dim_frame_among_the_settled_ones_is_skipped(self):
        found = self.launch(186.0)
        found[5] = Sample(found[5].t, card(100, contrast=20.0))
        self.assertEqual(cardframe.launch_settled_at(found, 0.0), 1.033)

    def test_a_tie_for_the_most_common_width_goes_to_the_later_one(self):
        widths = [150.0, 150.0, 160.0, 160.0, 165.0, 165.0, 170.0, 170.0]
        found = [Sample(round(1.0 + 0.017 * k, 3), card(100, left=16.0, right=16.0 + w)) for k, w in enumerate(widths)]
        self.assertEqual(cardframe.launch_settled_at(found, 0.0), 1.102)


class Detect(unittest.TestCase):
    def paper(self):
        return np.full((800, 400), float(PAPER), np.float32)

    def test_a_bright_rectangle_reads_as_its_edges_in_points_and_its_contrast(self):
        lum = self.paper()
        lum[200:520, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0), Card(100.0, 260.0, 16.0, 186.0, 40.0))

    def test_a_run_shorter_than_120_pt_is_no_card(self):
        lum = self.paper()
        lum[200:438, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0), None)

    def test_two_runs_split_by_a_gap_under_8_pt_are_one_card_and_8_pt_splits_them(self):
        lum = self.paper()
        lum[200:340, 32:372] = CARD
        lum[355:600, 32:372] = CARD
        self.assertEqual((cardframe.detect(lum, 2.0).top, cardframe.detect(lum, 2.0).bottom), (100.0, 300.0))
        lum[355, 32:372] = PAPER
        self.assertEqual((cardframe.detect(lum, 2.0).top, cardframe.detect(lum, 2.0).bottom), (178.0, 300.0))

    def test_a_card_over_the_paper_column_is_invisible(self):
        lum = self.paper()
        lum[200:520, 0:372] = CARD
        self.assertEqual(cardframe.detect(lum, 2.0), None)


def reading(rules=(), invalid="", animations="on", first_seen=0.0, lost=0, worst=0.0):
    return Reading(rules, invalid, animations, first_seen, lost, worst, 37, "12.31/14.02")


LOAD = "load 63.2 at the end, at or over 50"
RECORDER = "recorder exit 1 after SIGINT; the video may be cut short"
EARLY = "the recorder stopped before the take ended"
UNCOVERED = "the screen never changed after the drive began at +3.50 s, so the take shows nothing the drive did"


def results(*verdicts):
    return [TakeResult(spec.name, v, "" if v is Verdict.PASS else f"{v.value.lower()} reason")
            for spec, v in zip(cardstill.TAKES, verdicts)]


PASSES = [Verdict.PASS] * 8


class Takes(unittest.TestCase):
    def test_the_lane_is_the_eight_takes_of_the_original_in_order(self):
        self.assertEqual([(t.name, t.tail, t.setup.name) for t in cardstill.TAKES], [
            ("single-log-rest-start", 3, "LAUNCH"),
            ("node-tap", 2, "NONE"),
            ("review-open", 2, "NONE"),
            ("review-collapse", 2, "NONE"),
            ("superset-log-switch", 3, "LAUNCH_AND_PAIR"),
            ("partner-tap", 2, "NONE"),
            ("partner-tap-back", 2, "NONE"),
            ("superset-rest-end", 14, "AFTER_REST"),
        ])

    def test_each_take_drives_its_verb_and_only_the_rest_end_only_watches(self):
        self.assertEqual([t.drive for t in cardstill.TAKES], [
            ("tap", "--id", "log-active-set-button"),
            ("tap", "--label", cardstill.SetNode(3)),
            ("tap", "--label", cardstill.SetNode(1)),
            ("tap", "--label", "Collapse logged set"),
            ("tap", "--id", "log-active-set-button"),
            ("tap", "--id", "superset-partner-name"),
            ("tap", "--id", "superset-partner-name"),
            (),
        ])

    def test_a_set_node_resolves_to_its_label_in_the_tree(self):
        tree = ("AXButton\tlog-active-set-button\tLog 237.5 x 5 @6\t\t@20,700 362x50\n"
                "AXButton\t\tSet 1, 185 x 5, logged\t\t@20,300 40x40\n"
                "AXButton\t\tSet 3, 195 x 5\t\t@120,300 40x40\n")
        self.assertEqual(cardstill.node_label(tree, 3), "Set 3, 195 x 5")
        self.assertEqual(cardstill.node_label(tree, 1), "Set 1, 185 x 5, logged")
        self.assertEqual(cardstill.node_label(tree, 2), None)

    def test_record_and_launch_output_name_the_take_and_the_evidence_directory(self):
        record = "/e/lane-head/node-tap.mp4\n/e/lane-head/node-tap.take\ntake node-tap VALID 4.71 s, ...\n"
        launch = "launched session as pid 4121 on SIM (animations on)\napp 804e750cad00\nevidence /e/lane-head\n"
        self.assertEqual(cardstill.recorded_take(record), Path("/e/lane-head/node-tap.take"))
        self.assertEqual(cardstill.recorded_take("load 63 at or over 50 after 60s\n"), None)
        self.assertEqual(cardstill.evidence_dir(launch), Path("/e/lane-head"))


FAKE_VERIFY = """#!/bin/sh
echo "$VERIFY_RUN $*" >> "{dir}/calls"
case $1 in
  launch) [ ! -e "{dir}/alive" ] || exit 75; touch "{dir}/alive"; echo "evidence {dir}/$VERIFY_RUN" ;;
  stop) rm -f "{dir}/alive" ;;
  tree) printf 'AXButton\\t\\tSet 1, 185 x 5, logged\\t\\t@20,300 40x40\\nAXButton\\t\\tSet 3, 195 x 5\\t\\t@120,300 40x40\\n' ;;
  record)
    [ -e "{dir}/stamp.take" ] || exit 75
    mkdir -p "{dir}/$VERIFY_RUN"
    cp "{dir}/stamp.take" "{dir}/$VERIFY_RUN/$2.take"
    echo "{dir}/$VERIFY_RUN/$2.take" ;;
esac
"""


class Film(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        fake = self.dir / "verify.sh"
        fake.write_text(FAKE_VERIFY.replace("{dir}", str(self.dir)))
        fake.chmod(0o755)
        self.saved = cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_TAPS
        cardstill.VERIFY, cardstill.REST_END_AFTER_S = fake, 0.0
        cardstill.PAIR_TAPS = tuple((ident, 0) for ident, _ in cardstill.PAIR_TAPS)

    def tearDown(self):
        cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_TAPS = self.saved

    def test_each_relaunch_stops_the_side_s_app_first_so_launch_is_never_refused(self):
        results = cardstill.Side("lane-control", "7fefd137").film()
        calls = (self.dir / "calls").read_text().splitlines()
        self.assertEqual([c for c in calls if " launch " in c or c.endswith(" stop")], [
            "lane-control stop",
            "lane-control stop",
            "lane-control launch --at 7fefd137 --animated session",
            "lane-control stop",
            "lane-control launch --at 7fefd137 --animated session",
            "lane-control stop",
        ])
        self.assertEqual([cardstill.measured(r).reason for r in results],
                         ["record exited 75"] * 7 + ["the Superset log take left no stamp to time the rest end from"])

    def test_every_take_on_both_sides_is_filmed_before_any_is_measured(self):
        (self.dir / "stamp.take").write_text("\n".join(take.take_lines(dataclasses.replace(TAKE, started=1000.0)) + [
            "screen_pt=200x400", "animations=on", "app="]) + "\n")
        calls = self.dir / "calls"

        def measure(video):
            with calls.open("a") as log:
                log.write(f"measure {video.parent.name}/{video.stem}\n")
            return cardframe.summarize(TAKE, [Sample(0.0, card(100))], 0.0)

        self.addCleanup(setattr, cardframe, "measure", cardframe.measure)
        cardframe.measure = measure
        with mock.patch.dict(os.environ, {"SIM": "LANE", "VERIFY_RUN": "lane"}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = cardstill.main(["--control", "7fefd137"])
        lines = calls.read_text().splitlines()
        kinds = ["measure" if line.startswith("measure ") else "record" for line in lines
                 if line.startswith("measure ") or line.split()[1] == "record"]
        self.assertEqual(kinds, ["record"] * 16 + ["measure"] * 16)
        self.assertEqual(lines[-1], "measure lane-head/superset-rest-end")
        self.assertEqual(code, 3)


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
            (3, reading(rules=("load",), invalid=LOAD, first_seen=None), 0.0,
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
            (0, reading(animations="off", worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(animations="off"), 0.0, (Verdict.INVALID, "animations off")),
            (0, reading(animations="off", lost=2), 0.0, (Verdict.FAIL, "lost the card in 2 frames")),
            (0, reading(), 3.4, (Verdict.INVALID, "started 3.4 s late")),
            (0, reading(worst=412.0), 3.4, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(first_seen=None), 0.0, (Verdict.FAIL, "no card in any frame")),
            (0, reading(lost=27), 0.0, (Verdict.FAIL, "lost the card in 27 frames")),
            (0, reading(worst=412.0), 0.0, (Verdict.FAIL, "an edge moved 412.0 pt")),
            (0, reading(worst=0.6), 0.0, (Verdict.FAIL, "an edge moved 0.6 pt")),
            (0, reading(worst=0.5), 0.0, (Verdict.PASS, "")),
            (3, reading(), 0.0, (Verdict.PASS, "")),
        ]
        for record_exit, r, late, expected in cases:
            with self.subTest(record_exit=record_exit, reading=r, late=late):
                self.assertEqual(cardstill.judge_take(record_exit, r, late), expected)


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

    def test_a_still_head_over_a_control_that_moved_passes(self):
        control = results(Verdict.FAIL, Verdict.PASS, Verdict.FAIL, *[Verdict.PASS] * 5)
        self.assertEqual(cardstill.lane_verdict("ea5af074", control, results(*PASSES)), (
            Verdict.PASS, "the head held the card still on every take; the control ea5af074 moved it on 2"))

    def test_the_verdicts_exit_0_1_3(self):
        self.assertEqual(cardstill.EXIT, {Verdict.PASS: 0, Verdict.FAIL: 1, Verdict.INVALID: 3})


class Table(unittest.TestCase):
    def test_a_row_sets_control_and_head_side_by_side(self):
        control = [TakeResult("node-tap", Verdict.FAIL, "an edge moved 412.0 pt", reading(worst=412.0))]
        head = [TakeResult("node-tap", Verdict.INVALID, "record exited 75")]
        rows = cardstill.table(control, head)
        self.assertEqual(rows[0], [
            "take",
            "control_verdict", "control_worst_edge", "control_lost", "control_frames", "control_load",
            "control_reason",
            "head_verdict", "head_worst_edge", "head_lost", "head_frames", "head_load", "head_reason",
        ])
        self.assertEqual(rows[2], [
            "node-tap",
            "FAIL", "412.0", "0", "37", "12.31/14.02", "an edge moved 412.0 pt",
            "INVALID", "", "", "", "", "record exited 75",
        ])
        self.assertEqual(len(rows), 9)


if __name__ == "__main__":
    unittest.main()
