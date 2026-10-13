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
FIXTURES = SKILL / "tests" / "fixtures"
sys.path.insert(0, str(SKILL))
sys.path.insert(0, str(MOTION))
import cardframe  # noqa: E402
import take  # noqa: E402
import cardstill  # noqa: E402
from tree import Frame  # noqa: E402
from cardframe import Card, LookKind, Opened, Reason, Sample, Still, Window  # noqa: E402
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


TREE_INSET_PT = 4


def tree_frame_around(top, bottom, left, right):
    i = TREE_INSET_PT
    return f"@{left - i},{top - i} {right - left + 2 * i}x{bottom - top + 2 * i}"


RESTS = tree_frame_around(*STILL_BOX)


def stamp(video, drive="", drive_start=0.0, drive_end=0.0, load_after=14.02, animations="on", like=None,
          stopped=None, card_pt=RESTS):
    pts, size = take.probe(like or video)
    filmed = take.Take(
        name=video.stem, video=video.name, drive=drive, tail=2.0, load_limit=50.0, load_before=12.31,
        load_after=load_after, started=1791817306.217, drive_start=drive_start, drive_end=drive_end,
        stopped=round(max(pts[-1], drive_end) + 2.0, 3) if stopped is None else stopped, recorder_exit=0,
        recorder_early=False, frames=len(pts), first_frame=round(pts[0], 3), last_frame=round(pts[-1], 3),
        video_px=size)
    path = video.with_suffix(".take")
    path.write_text("\n".join(take.take_lines(filmed) + [
        f"screen_pt={SCREEN_PT[0]}x{SCREEN_PT[1]}",
        f"card_pt={card_pt}",
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


def drops_for_three_frames(i):
    return (PAPER + 3 * (i - FPS + 1), []) if FPS <= i < FPS + 3 else (PAPER, [STILL_BOX])


SPRINGBOARD_FRAMES = 18


def launched(app, fade_end=60, fade=20):
    fading_out, icons_alone = SPRINGBOARD_FRAMES - 6, SPRINGBOARD_FRAMES - 2
    def scene(i):
        icon = (100, 300, 12, 196)
        if i < fading_out:
            return PAPER, [icon]
        if i < icons_alone:
            k = (icons_alone - i) / (icons_alone - fading_out + 1)
            return round(PAPER * k), [icon + (round(CARD * k),)]
        if i == icons_alone:
            return 0, [icon + (round(CARD * 0.2),)]
        faded = i - fade_end + fade
        if faded <= 0:
            return 0, []
        if faded <= fade:
            k = faded / fade
            paper, boxes = app(0)
            return round(paper * k), [box[:4] + (round((box[4] if len(box) > 4 else CARD) * k),) for box in boxes]
        return app(faded - fade)
    return scene


def entered(j):
    return min(max((j - 5) / 24, 0.0), 1.0)


def fades_in_place(j):
    return PAPER, [STILL_BOX + (round(PAPER + (CARD - PAPER) * entered(j)),)]


def slides_in_from_the_right(j):
    shift = 184 * (1 - entered(j))
    return PAPER, [(100, 260, 16 + shift, min(186 + shift, SCREEN_PT[0]))]


def flies_in_from_the_top(j):
    return PAPER, [(100 * entered(j), 160 + 100 * entered(j), 16, 186)]


def jumps_20_pt_in_its_last_two_frames(j):
    return PAPER, [STILL_BOX if j < 30 else (100, 280, 16, 186) if j == 30 else (100, 280, 16, 196)]


def jumps_20_pt_in_its_last_frame(j):
    return PAPER, [STILL_BOX if j < 30 else (100, 280, 16, 186)]


def zooms_from_the_icon(i):
    k = min(max((i - 18) / 20, 0.0), 1.0)
    return PAPER, [(180 - 80 * k, 180 + 80 * k, 101 - 85 * k, 101 + 85 * k)]


def a_3_pt_rule_beside_a_ticking_box(i):
    return PAPER, [(270, 395, 101, 104), (20, 40, 100, 150, PAPER + 10 + 4 * (i // 6))]


def jumps_then_brightens_to_where_it_sits(i):
    if i < 30:
        return PAPER, [(100, 260, 16, 186, 225)]
    return PAPER, [(140, 300, 16, 186, 225 if i < 48 else CARD)]


def shrinks_from_240_pt_to_160_pt(i):
    return PAPER, [(100, 340 if i < 5 else 260, 16, 186), (360, 380, 100, 150, PAPER + 10 + 4 * min(i, 6))]


def swaps_a_label_inside(i):
    return PAPER, [STILL_BOX, (120, 160, 40, 80, CARD if i < FPS else 210)]


def run_cardframe(*args):
    done = subprocess.run(
        [sys.executable, str(MOTION / "cardframe.py"), *map(str, args)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    return done.returncode, done.stdout, done.stderr


LAUNCH_DRIVE = "launch --animated session"
SLID = tree_frame_around(200, 350, 16, 186)


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

    def test_an_invalid_take_is_measured_under_a_banner_reads_still_unknown_and_exits_3(self):
        code, out, _ = self.lines("ticking", load_after=63.2)
        self.assertEqual(code, 3)
        self.assertEqual(out[:3], [
            "INVALID take: load 63.2 at the end, at or over 50",
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


def card(top, bottom=None, left=16.0, right=186.0, contrast=40.0):
    return Card(top, top + 160 if bottom is None else bottom, left, right, contrast)


FLAT = np.full((100, 50), float(PAPER), np.float32)
DARK = np.zeros((100, 50), np.float32)


def lit(rows):
    cells = FLAT.copy()
    cells[:rows] += 1.0
    return cells


def frames(*cards, start=0.0):
    return [Sample(round(start + 0.1 * k, 3), c, FLAT) for k, c in enumerate(cards)]


TAKE = take.Take(
    name="x", video="x.mp4", drive="", tail=2.0, load_limit=50.0, load_before=1.0, load_after=1.0, started=0.0,
    drive_start=0.0, drive_end=0.0, stopped=3.0, recorder_exit=0, recorder_early=False, frames=2, first_frame=0.0,
    last_frame=1.0, video_px=(600, 1200), screen_pt=(200, 400), animations="on", card_pt=Frame(16, 100, 170, 160))


def held_at(c, at=TAKE):
    return dataclasses.replace(at, card_pt=Frame(c.left, c.top, c.right - c.left, c.bottom - c.top))
LAUNCH = dataclasses.replace(TAKE, drive="launch --animated session", drive_start=0.05, drive_end=1.0, stopped=4.0)
FADED_IN = [Sample(0.0, None, DARK), Sample(0.5, None, DARK + 100), Sample(0.6, card(100), FLAT),
            Sample(0.7, card(100), lit(64)), Sample(0.8, card(100), FLAT)]


def lum(value, rows=100):
    cells = DARK.copy()
    cells[:rows] = value
    return cells


def launch_frames(from_black=True, dim=False):
    springboard_fading_out = [Sample(0.0, None, lum(120)), Sample(0.1, None, lum(90)), Sample(0.12, None, lum(60)),
                              Sample(0.14, None, lum(30))]
    black = [Sample(0.16, None, lum(30, rows=60)), Sample(0.18, None, DARK), Sample(0.6, None, DARK)]
    fading_in_with_a_repeat = [Sample(0.8, None, lum(40)), Sample(0.85, None, lum(80)), Sample(0.9, None, lum(80)),
                               Sample(0.95, card(100), lum(120)), Sample(0.98, card(100), lum(160)),
                               Sample(1.0, card(100), FLAT)]
    sliding_200_pt = [Sample(round(1.0 + 0.1 * k, 3), card(100 + 50 * k), lit(10 * k)) for k in range(1, 5)]
    dimming = [Sample(round(2.7 + 0.02 * k, 3), card(300), FLAT * (1 - 0.05 * k)) for k in range(1, 5)]
    return (springboard_fading_out + (black if from_black else []) + fading_in_with_a_repeat + sliding_200_pt
            + (dimming if dim else []))


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


def looks(*insides):
    found = []
    for k, inside in enumerate(insides):
        cells = FLAT.copy()
        cells[cardframe.box_cells(card(100))] = inside
        found.append(Sample(round(0.1 * k, 3), card(100), cells))
    return found


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


def reading(rules=(), invalid="", animations="on", no_card=None, lost=0, faint=0, partial=False, worst=0.0,
            look="still"):
    first = [card(100, contrast=5.0)] * faint + ([None] if partial and not faint else [])
    m = cardframe.summarize(dataclasses.replace(TAKE, animations=animations), frames(*first, card(100)), 0.0)
    m = dataclasses.replace(m, invalid=(Reason(",".join(rules), invalid),) if rules else ())
    return dataclasses.replace(Reading.of(m), rules=rules, no_card=no_card, lost=lost, worst_edge_range=worst,
                               look=look, frames=37, load="12.31/14.02")


LOAD = "load 63.2 at the end, at or over 50"
RECORDER = "recorder exit 1 after SIGINT; the video may be cut short"
EARLY = "the recorder stopped before the take ended"
UNCOVERED = "the screen never changed after the drive began at +3.50 s, so the take shows nothing the drive did"
SHORT = "the window watched 0.90 s from +2.500 s, under 1.5 s"
NO_FRAMES = "none of the 37 frames from 0.000 s showed it"
NO_FADE = ("no frame after the launch began changed three quarters of the screen, so iOS's fade-in cannot be told "
           "from the app's motion")


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

    def test_each_take_lands_on_the_screen_its_drive_leads_to_and_not_on_the_one_before(self):
        before_after = [
            (LAUNCHED, LOGGED), (LOGGED, NODE_3), (NODE_3, REVIEW), (REVIEW, COLLAPSED),
            (PAIRED, SWITCHED), (SWITCHED, PARTNER), (PARTNER, SWITCHED), (SWITCHED, RESTED),
        ]
        landed, stayed = [], []
        for spec, (before, after) in zip(cardstill.TAKES, before_after):
            landed.append(cardstill.landing_miss(spec, ended_on(after)))
            stayed.append(cardstill.landing_miss(spec, ended_on(before)))
        self.assertEqual(landed, [None] * 8)
        self.assertEqual(stayed, [
            'the take ended without "Set 2 of 3"',
            'the take ended without "Set 3 of 3"',
            'the take ended without "Collapse logged set"',
            'the take ended with "Collapse logged set" still on screen',
            'the take ended without stage-exercise-name "BB RDL"',
            'the take ended without stage-exercise-name "Back Squat"',
            'the take ended without stage-exercise-name "BB RDL"',
            "the take ended with rest-pill still on screen",
        ])
        self.assertEqual(cardstill.landing_miss(cardstill.TAKES[3], ended_on(LOGGED)),
                         'the take ended without "Set 3 of 3"', "a closed review on another Set did not land")
        self.assertEqual(cardstill.landing_miss(cardstill.TAKES[7], ended_on(screen(SQUAT, card_heading(2, 3)))),
                         'the take ended without stage-exercise-name "BB RDL"', "a rest that ended off the partner")

    def test_a_take_with_no_end_tree_beside_its_stamp_did_not_show_it_landed(self):
        self.assertEqual(cardstill.landing_miss(cardstill.TAKES[1], Path(tempfile.mkdtemp()) / "node-tap.take"),
                         "record left no node-tap.end.txt to check the take landed")


def screen(*lines):
    return "".join("\t".join(fields) + "\n" for fields in lines)


SQUAT = ("AXStaticText", "stage-exercise-name", "Back Squat", "", "@16,133 173x41")
RDL = ("AXStaticText", "stage-exercise-name", "BB RDL", "", "@16,163 123x41")
RESTING = ("AXGenericElement", "rest-pill", "Rest, 1 minute 56 seconds remaining", "", "@16,786 202x51")


def card_heading(n, of):
    return ("AXStaticText", "", f"Set {n} of {of}", "", "@32,492 59x23")


LAUNCHED = screen(SQUAT, card_heading(1, 3), ("AXButton", "log-active-set-button", "Log 237.5 × 5 @6", "",
                                              "@32,712 338x58"))
LOGGED = screen(SQUAT, card_heading(2, 3), RESTING)
NODE_3 = screen(SQUAT, card_heading(3, 3), RESTING)
REVIEW = screen(SQUAT, ("AXButton", "chevron.up", "Collapse logged set", "", "@338,481 44x44"), card_heading(1, 3),
                ("AXGenericElement", "logged-set-capsule", "237.5x5@6", "", "@32,712 338x58"), RESTING)
COLLAPSED = NODE_3
PAIRED = screen(SQUAT, ("AXButton", "superset-partner-name", "& BB RDL", "", "@16,177 94x25"), card_heading(1, 3))
SWITCHED = screen(RDL, ("AXButton", "superset-partner-name", "& Back Squat", "", "@16,207 125x25"),
                  card_heading(1, 2), RESTING)
PARTNER = screen(SQUAT, ("AXButton", "superset-partner-name", "& BB RDL", "", "@16,177 94x25"), card_heading(2, 3),
                 RESTING)
RESTED = screen(RDL, ("AXButton", "superset-partner-name", "& Back Squat", "", "@16,207 125x25"), card_heading(1, 2))


def ended_on(tree):
    take_path = Path(tempfile.mkdtemp()) / "x.take"
    take_path.with_suffix(".end.txt").write_text(tree)
    return take_path


FAKE_VERIFY = """#!/bin/sh
echo "$VERIFY_RUN $*" >> "{dir}/calls"
case $1 in
  launch) [ ! -e "{dir}/alive" ] || exit 75; touch "{dir}/alive"; echo "evidence {dir}/$VERIFY_RUN" ;;
  stop) rm -f "{dir}/alive" ;;
  tree)
    if [ -e "{dir}/tree.fails" ]; then rm "{dir}/tree.fails"; exit 1; fi
    cat "{dir}/tree"; [ ! -e "{dir}/tree.next" ] || mv "{dir}/tree.next" "{dir}/tree" ;;
  record)
    [ -e "{dir}/stamp.take" ] || exit 75
    mkdir -p "{dir}/$VERIFY_RUN"
    cp "{dir}/stamp.take" "{dir}/$VERIFY_RUN/$2.take"
    [ ! -e "{dir}/end/$VERIFY_RUN/$2" ] || cp "{dir}/end/$VERIFY_RUN/$2" "{dir}/$VERIFY_RUN/$2.end.txt"
    echo "{dir}/$VERIFY_RUN/$2.take" ;;
esac
"""


class Film(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        fake = self.dir / "verify.sh"
        fake.write_text(FAKE_VERIFY.replace("{dir}", str(self.dir)))
        fake.chmod(0o755)
        (self.dir / "tree").write_text("AXButton\t\tSet 1, 185 x 5, logged\t\t@20,300 40x40\n"
                                       "AXButton\t\tSet 3, 195 x 5\t\t@120,300 40x40\n"
                                       "AXButton\tstage-queue-superset\tSuperset\t\t@334,432 44x44\n")
        self.saved = cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_TAPS, cardstill.PAIR_WAIT_S
        cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_WAIT_S = fake, 0.0, 0.0
        cardstill.PAIR_TAPS = tuple((ident, 0) for ident, _ in cardstill.PAIR_TAPS)

    def tearDown(self):
        cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_TAPS, cardstill.PAIR_WAIT_S = self.saved

    def pair_taps(self, queue_tree):
        (self.dir / "tree").write_text((FIXTURES / queue_tree).read_text())
        with contextlib.redirect_stderr(io.StringIO()):
            cardstill.Side("lane-head", None).pair()
        return [c.split(" ", 1)[1] for c in (self.dir / "calls").read_text().splitlines() if " tap " in c]

    def test_an_app_after_ui_11_pairs_through_the_queue_s_superset_button(self):
        self.assertEqual(self.pair_taps("04-queue-superset.tree.txt"), [
            "tap --id stage-queue-button",
            "tap --id stage-queue-superset",
            "tap --id stage-queue-row-exercise-1",
            "tap --id stage-queue-row-superset-0",
        ])

    def test_an_app_before_ui_11_pairs_through_the_first_row_s_pair_button(self):
        self.assertEqual(self.pair_taps("03-queue.all.txt"), [
            "tap --id stage-queue-button",
            "tap --id stage-queue-pair-exercise-0",
            "tap --id stage-queue-row-exercise-1",
            "tap --id stage-queue-row-superset-0",
        ])

    def test_pairing_opens_the_queue_then_reads_the_tree_until_the_sheet_shows_its_way_in(self):
        (self.dir / "tree.next").write_text((FIXTURES / "04-queue-superset.tree.txt").read_text())
        cardstill.PAIR_WAIT_S = 2.0
        self.pair_taps("01-before.tree.txt")
        self.assertEqual((self.dir / "calls").read_text().splitlines()[:4], [
            "lane-head tap --id stage-queue-button",
            "lane-head tree",
            "lane-head tree",
            "lane-head tap --id stage-queue-superset",
        ])

    def test_a_failed_tree_read_while_the_sheet_opens_is_read_again(self):
        (self.dir / "tree.fails").touch()
        cardstill.PAIR_WAIT_S = 2.0
        self.assertEqual(self.pair_taps("04-queue-superset.tree.txt")[1], "tap --id stage-queue-superset")

    def test_a_queue_with_neither_way_into_pairing_fails_the_setup_after_one_tap(self):
        with self.assertRaises(cardstill.SetupFailed) as raised:
            self.pair_taps("01-before.tree.txt")
        self.assertEqual(str(raised.exception),
                         "the queue showed neither stage-queue-superset (since UI-11 (#857)) nor "
                         "stage-queue-pair-exercise-0 (before UI-11, as every control whose card moves)")
        self.assertEqual([c for c in (self.dir / "calls").read_text().splitlines() if " tap " in c],
                         ["lane-head tap --id stage-queue-button"])

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
            return cardframe.summarize(TAKE, [Sample(0.0, card(100), FLAT)], 0.0)

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

    def lane(self, side, node_tap_ends_on):
        (self.dir / "stamp.take").write_text("\n".join(take.take_lines(dataclasses.replace(TAKE, started=1000.0)) + [
            "screen_pt=200x400", "animations=on", "app="]) + "\n")
        ends = [LOGGED, NODE_3, REVIEW, COLLAPSED, SWITCHED, PARTNER, SWITCHED, RESTED]
        for run in ("lane-control", "lane-head"):
            (self.dir / "end" / run).mkdir(parents=True)
            for spec, tree in zip(cardstill.TAKES, ends):
                (self.dir / "end" / run / spec.name).write_text(tree)
        (self.dir / "end" / side / "node-tap").write_text(node_tap_ends_on)

        def measure(video):
            moved = video.parent.name == "lane-control" and video.stem == "node-tap"
            return cardframe.summarize(TAKE, frames(*([card(80)] if moved else []), card(100), card(100)), 0.0)

        self.addCleanup(setattr, cardframe, "measure", cardframe.measure)
        cardframe.measure = measure
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"SIM": "LANE", "VERIFY_RUN": "lane"}), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = cardstill.main(["--control", "7fefd137"])
        return code, out.getvalue().splitlines()[-1]

    def test_a_head_drive_that_left_the_screen_as_it_was_is_invalid_though_its_card_held_still(self):
        self.assertEqual(self.lane("lane-head", node_tap_ends_on=LOGGED), (
            3, 'cardstill INVALID: head node-tap: the take ended without "Set 3 of 3"'))

    def test_a_control_drive_that_did_not_land_is_invalid_though_its_card_moved(self):
        self.assertEqual(self.lane("lane-control", node_tap_ends_on=LOGGED), (
            3, 'cardstill INVALID: control node-tap: the take ended without "Set 3 of 3"'))

    def test_the_same_lane_passes_when_that_drive_landed(self):
        self.assertEqual(self.lane("lane-head", node_tap_ends_on=NODE_3), (
            0, "cardstill PASS: the head held the card still on every take; the control 7fefd137 moved it on 1"))


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


if __name__ == "__main__":
    unittest.main()
