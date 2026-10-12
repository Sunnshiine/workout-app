#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""cardframe.py on clips encoded the way simctl writes them, and cardstill.py's verdicts. No simulator.

  uv run .agents/skills/verify/tests/test_motion.py      (needs ffmpeg and ffprobe on PATH)
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

MOTION = Path(__file__).resolve().parent.parent / "motion"
sys.path.insert(0, str(MOTION))
import cardframe  # noqa: E402
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
    """scene(i) -> (paper level, [(top, bottom, left, right) in pt]) for frame i at 60 fps."""
    w, h = (n * VIDEO_PX_PER_PT for n in SCREEN_PT)
    for i in range(round(seconds * FPS)):
        paper, boxes = scene(i)
        img = np.full((h, w), paper, np.uint8)
        for box in boxes:
            top, bottom, left, right = box[:4]
            s = VIDEO_PX_PER_PT
            img[round(top * s):round(bottom * s), round(left * s):round(right * s)] = box[4] if len(box) > 4 else CARD
        yield img


def encode(path, scene, seconds):
    """Keeps only the frames that changed, each at its own time, as simctl's recordVideo does."""
    w, h = (n * VIDEO_PX_PER_PT for n in SCREEN_PT)
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray", "-s", f"{w}x{h}",
         "-framerate", str(FPS), "-i", "-", "-vf", "mpdecimate=hi=1:lo=1:frac=0", "-fps_mode", "vfr",
         "-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv420p", str(path)],
        stdin=subprocess.PIPE,
    )
    for img in scene_frames(scene, seconds):
        proc.stdin.write(img.tobytes())
    proc.stdin.close()
    assert proc.wait() == 0, f"ffmpeg could not encode {path}"


def stamp(video, drive="", drive_start="", drive_end="", verdict="VALID", invalid="", animations="on"):
    take = video.with_suffix(".take")
    take.write_text("\n".join([
        "format=take/1",
        f"name={video.stem}",
        f"video={video.name}",
        f"drive={drive}",
        "tail=2.0",
        "load_limit=50",
        "load_before=12.31",
        "load_after=14.02",
        "started=1791817306.217",
        f"drive_start={drive_start}",
        f"drive_end={drive_end}",
        "stopped=4.714",
        "recorder_exit=0",
        "recorder_early=0",
        "frames=0",
        "first_frame=0.000",
        "last_frame=0.000",
        f"video_px={SCREEN_PT[0] * VIDEO_PX_PER_PT}x{SCREEN_PT[1] * VIDEO_PX_PER_PT}",
        f"verdict={verdict}",
        f"invalid={invalid}",
        f"screen_pt={SCREEN_PT[0]}x{SCREEN_PT[1]}",
        f"animations={animations}",
        "app=app 804e750cad00 commit ea5af074 (this worktree's build)",
    ]) + "\n")
    return take


def still(i):
    return PAPER, [STILL_BOX]


def slide(i):
    """Still for 1 s, then the card slides 160 pt down over 0.4 s and stops."""
    t = i / FPS
    progress = min(max((t - 1.0) / 0.4, 0.0), 1.0)
    top = 40 + 160 * progress
    return PAPER, [(top, top + 150, 16, 186)]


def cuts(i):
    """Still for 1 s, then the card jumps 160 pt down in one frame and stays."""
    top = 40 if i < FPS else 200
    return PAPER, [(top, top + 150, 16, 186)]


def zoomed(box, scale):
    top, bottom, left, right = box
    cy, cx, h, w = (top + bottom) / 2, (left + right) / 2, (bottom - top) * scale, (right - left) * scale
    return (cy - h / 2, cy + h / 2, cx - w / 2, cx + w / 2)


def fades_in(i):
    """A launch under -UITEST_DISABLE_ANIMATIONS: black frames a shade apart until 1.0 s, then the whole
    screen fading up from black over 10 frames, the card's contrast with it."""
    if i < FPS:
        return 10 + 3 * i, []
    k = min((i - FPS + 1) / 10, 1.0)
    return round(PAPER * k), [STILL_BOX + (round(CARD * k),)]


def launches(slide_after=0.0):
    """A launch: 0.3 s of springboard holding a wider card-like box, black frames a shade apart until 1.0 s,
    the app's window scaling up from 0.8 over 6 frames, then the card, which slides up by slide_after pt over
    0.3 s when slide_after is set."""
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
    """The card for 1 s, three frames of bare paper (each a shade apart, so all three are encoded), then back."""
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
            ("slide", slide, 2.0),
            ("cut", cuts, 2.0),
            ("launch", launches(), 1.5),
            ("launch-slide", launches(slide_after=40), 1.5),
            ("launch-fade", fades_in, 1.5),
            ("drop", drops_for_three_frames, 1.5),
        ]:
            cls.clips[name] = cls.dir / f"{name}.mp4"
            encode(cls.clips[name], scene, seconds)

    def test_a_still_card_is_one_encoded_frame_and_reads_still(self):
        video = self.clips["still"]
        stamp(video)
        code, out, err = run_cardframe(video)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines(), [
            "take=VALID animations=on frames=1 window_frames=1",
            "first_seen=0.000 lost=0",
            "top=100.0..100.0 bottom=260.0..260.0 left=16.0..16.0 right=186.0..186.0",
            "worst_edge_range=0.0",
            "contrast=40.0..40.0",
            "motion=none",
            "still=yes",
        ])

    def test_a_slide_of_160_pt_over_400_ms_reads_its_range_and_duration_by_frame_time(self):
        video = self.clips["slide"]
        stamp(video, drive="tap --id log-active-set-button", drive_start="0.000", drive_end="0.500")
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
        stamp(video, drive="tap --id log-active-set-button", drive_start="0.300", drive_end="0.500")
        m = cardframe.measure(video)
        self.assertEqual((m.frames, len(m.window)), (2, 2))
        self.assertEqual((m.first_seen, m.worst_edge_range, m.changed_frames, m.still), (0.0, 160.0, 1, False))

    def test_the_tsv_has_a_row_per_window_frame_timed_from_the_drive(self):
        video = self.clips["slide"]
        stamp(video, drive="tap --id log-active-set-button", drive_start="0.500", drive_end="0.600")
        tsv = self.dir / "slide.tsv"
        code, _, err = run_cardframe(video, "--from", "0", "--tsv", tsv)
        self.assertEqual(code, 0, err)
        rows = tsv.read_text().splitlines()
        self.assertEqual(rows[:3], [
            "t\tt_from_drive\ttop\tbottom\tleft\tright\tcontrast",
            "0.000\t-0.500\t40.0\t190.0\t16.0\t186.0\t40.0",
            "1.017\t0.517\t46.5\t197.0\t16.0\t186.0\t39.9",
        ])
        self.assertEqual(len(rows), 26)

    def test_from_starts_at_the_frame_showing_then_and_rebases_the_card(self):
        video = self.clips["slide"]
        stamp(video)
        m = cardframe.measure(video, from_s=1.19)
        self.assertEqual(round(m.first_seen, 3), 1.183)
        self.assertEqual(m.ranges["top"], (113.0, 200.0))
        self.assertEqual(len(m.window), 14)

    def test_a_launch_is_measured_from_the_card_at_full_width_so_the_system_zoom_reads_still(self):
        video = self.clips["launch"]
        stamp(video, drive="launch --animated session", drive_start="0.000", drive_end="1.400")
        m = cardframe.measure(video)
        self.assertEqual((round(m.first_seen, 3), m.lost, m.worst_edge_range, m.still), (1.1, 0, 0.0, True))

    def test_a_launch_that_fades_in_is_measured_once_the_card_has_its_contrast(self):
        video = self.clips["launch-fade"]
        stamp(video, drive="launch session", drive_start="0.000", drive_end="1.400")
        m = cardframe.measure(video)
        self.assertEqual((round(m.first_seen, 3), m.worst_edge_range, m.still), (1.133, 0.0, True))

    def test_a_card_that_slides_in_after_the_launch_zoom_reads_its_slide(self):
        video = self.clips["launch-slide"]
        stamp(video, drive="launch --animated session", drive_start="0.000", drive_end="1.400")
        m = cardframe.measure(video)
        self.assertEqual((round(m.first_seen, 3), m.lost, m.ranges["top"], m.still), (1.1, 0, (100.0, 140.0), False))
        self.assertEqual((round(m.motion[0], 3), round(m.motion[1], 3)), (1.117, 1.4))

    def test_from_0_on_a_launch_reads_the_springboard_and_the_zoom_as_motion(self):
        video = self.clips["launch"]
        stamp(video, drive="launch --animated session", drive_start="0.000", drive_end="1.400")
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
        video = self.clips["still"]
        stamp(video, verdict="INVALID", invalid="load 63.2 at the end, at or over 50")
        code, out, _ = run_cardframe(video)
        self.assertEqual(code, 3)
        self.assertEqual(out.splitlines()[:3], [
            "INVALID take: load 63.2 at the end, at or over 50",
            "take=INVALID animations=on frames=1 window_frames=1",
            "first_seen=0.000 lost=0",
        ])

    def test_a_take_with_animations_off_exits_3_under_a_banner(self):
        video = self.clips["still"]
        stamp(video, animations="off")
        code, out, _ = run_cardframe(video)
        self.assertEqual(code, 3)
        self.assertEqual(out.splitlines()[0], "animations off: this take cannot show motion")
        self.assertEqual(out.splitlines()[-1], "still=yes")

    def test_no_card_in_the_window_exits_1(self):
        video = self.clips["still"]
        stamp(video)
        code, out, err = run_cardframe(video, "--x", "190")
        self.assertEqual(code, 1)
        self.assertEqual(out, "take=VALID animations=on frames=1 window_frames=1\n")
        self.assertEqual(err, "no card in any of the 1 frames from 0.000 s\n")

    def test_a_video_with_no_take_beside_it_exits_2_naming_the_stamp(self):
        video = self.dir / "unstamped.mp4"
        video.write_bytes(self.clips["still"].read_bytes())
        code, _, err = run_cardframe(video)
        self.assertEqual(code, 2)
        self.assertEqual(err, f"no take stamp {self.dir / 'unstamped.take'}; record the video with verify.sh record\n")

    def test_a_file_ffprobe_cannot_read_exits_70(self):
        video = self.dir / "broken.mp4"
        video.write_bytes(b"not a video")
        stamp(video)
        code, _, err = run_cardframe(video)
        self.assertEqual(code, 70)
        self.assertTrue(err.startswith(f"ffprobe could not read {video}"), err)


def card(top, bottom=None, left=16.0, right=186.0, contrast=40.0):
    return Card(top, top + 160 if bottom is None else bottom, left, right, contrast)


class Summarize(unittest.TestCase):
    def take(self):
        return cardframe.Take(Path("x.take"), "VALID", "", "on", "", None, None, "1.0", "1.0", (200, 400), (600, 1200))

    def test_a_cut_is_one_changed_frame_of_zero_duration(self):
        m = cardframe.summarize(self.take(), [Sample(0.0, card(100)), Sample(1.0, card(260))], 0.0)
        self.assertEqual((m.worst_edge_range, m.motion, m.motion_ms, m.changed_frames, m.still),
                         (160.0, (1.0, 1.0), 0, 1, False))

    def test_a_move_under_three_quarters_of_a_point_is_not_motion_but_counts_against_still(self):
        m = cardframe.summarize(self.take(), [Sample(0.0, card(100)), Sample(0.5, card(100.5))], 0.0)
        self.assertEqual((m.worst_edge_range, m.motion, m.changed_frames, m.still), (0.5, None, 0, True))
        m = cardframe.summarize(self.take(), [Sample(0.0, card(100)), Sample(0.5, card(100.6))], 0.0)
        self.assertEqual(m.still, False)

    def test_frames_without_the_card_before_it_shows_are_not_lost_and_after_it_are(self):
        samples = [Sample(0.0, None), Sample(0.1, None), Sample(0.2, card(100)), Sample(0.3, None),
                   Sample(0.4, card(100))]
        m = cardframe.summarize(self.take(), samples, 0.0)
        self.assertEqual((m.first_seen, m.lost, m.still), (0.2, 1, False))

    def test_motion_skips_a_lost_frame_and_compares_the_cards_either_side(self):
        samples = [Sample(0.0, card(100)), Sample(0.1, None), Sample(0.2, card(110)), Sample(0.3, card(110))]
        m = cardframe.summarize(self.take(), samples, 0.0)
        self.assertEqual((m.motion, m.changed_frames), ((0.2, 0.2), 1))

    def test_a_window_with_no_card_has_no_first_seen_and_is_not_still(self):
        m = cardframe.summarize(self.take(), [Sample(0.0, None), Sample(1.0, None)], 0.5)
        self.assertEqual((len(m.window), m.first_seen, m.lost, m.still), (2, None, 0, False))

    def test_the_frame_showing_at_from_opens_the_window(self):
        m = cardframe.summarize(self.take(), [Sample(0.0, card(100)), Sample(0.4, card(120)), Sample(1.0, None)], 0.5)
        self.assertEqual((len(m.window), m.first_seen, m.lost, m.ranges["top"]), (2, 0.4, 1, (120.0, 120.0)))


class Detect(unittest.TestCase):
    def paper(self):
        return np.full((800, 400), float(PAPER), np.float32)

    def test_a_bright_rectangle_reads_as_its_edges_in_points_and_its_contrast(self):
        lum = self.paper()
        lum[200:520, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum), Card(100.0, 260.0, 16.0, 186.0, 40.0))

    def test_a_run_shorter_than_120_pt_is_no_card(self):
        lum = self.paper()
        lum[200:438, 32:372] = CARD
        self.assertEqual(cardframe.detect(lum), None)

    def test_two_runs_split_by_a_gap_under_8_pt_are_one_card_and_8_pt_splits_them(self):
        lum = self.paper()
        lum[200:340, 32:372] = CARD
        lum[355:600, 32:372] = CARD
        self.assertEqual((cardframe.detect(lum).top, cardframe.detect(lum).bottom), (100.0, 300.0))
        lum[355, 32:372] = PAPER
        self.assertEqual((cardframe.detect(lum).top, cardframe.detect(lum).bottom), (178.0, 300.0))

    def test_a_card_over_the_paper_column_is_invisible(self):
        lum = self.paper()
        lum[200:520, 0:372] = CARD
        self.assertEqual(cardframe.detect(lum), None)


def reading(verdict="VALID", invalid="", animations="on", first_seen=0.0, lost=0, worst=0.0):
    return Reading(verdict, invalid, animations, first_seen, lost, worst, 37, "12.31/14.02")


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


class JudgeTake(unittest.TestCase):
    def test_the_truth_table(self):
        cases = [
            (75, reading(), 0.0, (Verdict.INVALID, "record exited 75")),
            (1, None, 0.0, (Verdict.INVALID, "record exited 1")),
            (0, None, 0.0, (Verdict.INVALID, "record left no stamp")),
            (3, reading(verdict="INVALID", invalid="load 63.2 at the end, at or over 50"), 0.0,
             (Verdict.INVALID, "take INVALID: load 63.2 at the end, at or over 50")),
            (3, reading(verdict="INVALID", invalid="load 63.2 at the end, at or over 50", first_seen=None), 0.0,
             (Verdict.INVALID, "take INVALID: load 63.2 at the end, at or over 50")),
            (3, reading(verdict="INVALID", invalid="load 63.2 at the end, at or over 50", worst=412.0), 0.0,
             (Verdict.FAIL, "an edge moved 412.0 pt")),
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
