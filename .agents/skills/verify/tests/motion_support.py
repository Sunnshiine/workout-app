"""Imports, paths, and the scenes, frames, and screens that more than one test_motion_* module uses."""
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


def looks(*insides):
    found = []
    for k, inside in enumerate(insides):
        cells = FLAT.copy()
        cells[cardframe.box_cells(card(100))] = inside
        found.append(Sample(round(0.1 * k, 3), card(100), cells))
    return found


def results(*verdicts):
    return [TakeResult(spec.name, v, "" if v is Verdict.PASS else f"{v.value.lower()} reason")
            for spec, v in zip(cardstill.TAKES, verdicts)]


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
REVIEW = screen(SQUAT, card_heading(1, 3),
                ("AXGenericElement", "logged-set-capsule", "237.5x5@6", "", "@32,712 338x58"), RESTING)
COLLAPSED = NODE_3
PAIRED = screen(SQUAT, ("AXButton", "superset-partner-name", "& BB RDL", "", "@16,177 94x25"), card_heading(1, 3))
SWITCHED = screen(RDL, ("AXButton", "superset-partner-name", "& Back Squat", "", "@16,207 125x25"),
                  card_heading(1, 2), RESTING)
PARTNER = screen(SQUAT, ("AXButton", "superset-partner-name", "& BB RDL", "", "@16,177 94x25"), card_heading(2, 3),
                 RESTING)
RESTED = screen(RDL, ("AXButton", "superset-partner-name", "& Back Squat", "", "@16,207 125x25"), card_heading(1, 2))
