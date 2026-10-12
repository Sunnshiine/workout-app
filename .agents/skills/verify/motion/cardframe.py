#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""The Active Set Card's edges, in points, in every encoded frame of a `verify.sh record` take.

  uv run .agents/skills/verify/motion/cardframe.py <run>/NAME.mp4 [--tsv PATH] [--from S] [--x 28] [--ref 8]

Reads NAME.take beside the video. Each encoded frame is decoded once, at the recording's own pixels
(video width over the stamp's screen_pt width per point), and timed by its own presentation time, in
seconds after the take started. recordVideo writes a frame only when the screen changes, so
the window is the frame showing at --from and every frame after it. --from is by default the drive's start
(0 with no drive). For a launch take it is the frame from which the card keeps the most common width of
the take's last eight cards and nine tenths of their median contrast, one stray frame aside: iOS opens an
app by scaling its window up from the icon, or by fading it in from black under -UITEST_DISABLE_ANIMATIONS,
and until then the system, not the app, moves the card's edges. An app's own scale-in or fade-in on launch
therefore reads as part of the launch, and a first-appear motion that overlaps the launch zoom is measured
only from when the zoom ends (a 300 pt slide in on first appear read 23 pt).
The card is the longest vertical run, at least 120 pt with gaps up to 8 pt merged, where the column at
--x pt is brighter than the paper column at --ref pt by 4.0; left and right come from a row scan at the
run's middle. Frames before the card first shows are not lost; a frame after it without the card is.

Prints key=value lines:
  take=VALID animations=on frames=111 window_frames=110
  first_seen=0.280 lost=83
  top=469.5..521.5 bottom=613.5..819.5 left=9.0..16.0 right=364.0..402.0
  worst_edge_range=206.0
  contrast=11.5..16.9
  motion=3.177..3.528 motion_ms=352 changed_frames=22
  still=no
motion spans the first and last frame whose edges moved more than 0.75 pt from the previous frame with
the card (motion=none when none did). still=yes when the card was seen, never lost, and no edge ranged
over more than 0.5 pt. --tsv writes one row per window frame: t, t_from_drive, top, bottom, left, right,
contrast, blank cells for a frame with no card.

Exit 0 measured, 1 no card in any window frame, 3 measured but the take is INVALID or its animations are
not on (a banner line first), 2 usage or no readable NAME.take with a screen_pt=, 70 ffmpeg or ffprobe
failed.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Dict, Iterator, List, Optional, Sequence, Tuple

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from take import NoTake, Take, judge, parse, probe  # noqa: E402

THRESHOLD = 4.0
MIN_RUN_PT = 120.0
MERGE_GAP_PT = 8.0
STILL_PT = 0.5
STEP_PT = 0.75
LAUNCH_CONTRAST = 0.9
SETTLED_FRAMES = 8
EDGES = ("top", "bottom", "left", "right")


class Usage(Exception):
    pass


class DecodeFailure(Exception):
    pass


@dataclass(frozen=True)
class Card:
    """Edges in points; contrast is the mean column contrast over the card's run."""

    top: float
    bottom: float
    left: float
    right: float
    contrast: float

    def edge(self, name: str) -> float:
        return getattr(self, name)


@dataclass(frozen=True)
class Sample:
    t: float
    card: Optional[Card]


def _band(pt: float, px_per_pt: float) -> slice:
    px = int(pt * px_per_pt)
    return slice(px - 2, px + 3)


def _runs(mask: np.ndarray, px_per_pt: float) -> List[Tuple[int, int]]:
    runs: List[Tuple[int, int]] = []
    start = None
    for y, on in enumerate(mask):
        if on and start is None:
            start = y
        if not on and start is not None:
            runs.append((start, y - 1))
            start = None
    if start is not None:
        runs.append((start, len(mask) - 1))
    merged: List[Tuple[int, int]] = []
    for run in runs:
        if merged and run[0] - merged[-1][1] <= MERGE_GAP_PT * px_per_pt:
            merged[-1] = (merged[-1][0], run[1])
        else:
            merged.append(run)
    return merged


def detect(lum: np.ndarray, px_per_pt: float, x_pt: float = 28, ref_pt: float = 8) -> Optional[Card]:
    card_band, paper_band = _band(x_pt, px_per_pt), _band(ref_pt, px_per_pt)
    contrast = lum[:, card_band].mean(axis=1) - lum[:, paper_band].mean(axis=1)
    runs = [r for r in _runs(contrast > THRESHOLD, px_per_pt) if (r[1] - r[0]) / px_per_pt >= MIN_RUN_PT]
    if not runs:
        return None
    start, end = max(runs, key=lambda r: r[1] - r[0])
    middle = (start + end) // 2
    row = lum[max(0, middle - 2):middle + 3].mean(axis=0)
    on = np.where(row - row[paper_band].mean() > THRESHOLD)[0]
    left = on[0] / px_per_pt if len(on) else math.nan
    right = (on[-1] + 1) / px_per_pt if len(on) else math.nan
    return Card(
        top=start / px_per_pt,
        bottom=(end + 1) / px_per_pt,
        left=float(left),
        right=float(right),
        contrast=float(contrast[start:end + 1].mean()),
    )


@dataclass(frozen=True)
class Measure:
    take: Take
    frames: int
    from_s: float
    window: Tuple[Sample, ...]
    first_seen: Optional[float]
    lost: int
    ranges: Dict[str, Tuple[float, float]]
    worst_edge_range: float
    contrast: Optional[Tuple[float, float]]
    motion: Optional[Tuple[float, float]]
    changed_frames: int
    still: bool

    @property
    def motion_ms(self) -> Optional[int]:
        return None if self.motion is None else round((self.motion[1] - self.motion[0]) * 1000)

    @property
    def invalid(self) -> List[str]:
        return judge(self.take)


def summarize(take: Take, samples: Sequence[Sample], from_s: float) -> Measure:
    # A frame stands on screen until the next one, so the frame showing at from_s opens the window.
    showing = [s for s in samples if s.t <= from_s][-1:]
    window = tuple(showing) + tuple(s for s in samples if s.t > from_s)
    seen = next((i for i, s in enumerate(window) if s.card is not None), None)
    after = window[seen:] if seen is not None else ()
    cards = [s for s in after if s.card is not None]
    ranges = {}
    for name in EDGES:
        values = [s.card.edge(name) for s in cards]
        ranges[name] = (float(np.nanmin(values)), float(np.nanmax(values))) if values else (math.nan, math.nan)
    moved = [
        b.t for a, b in zip(cards, cards[1:])
        if any(abs(a.card.edge(n) - b.card.edge(n)) > STEP_PT for n in EDGES)
    ]
    worst = max((hi - lo for lo, hi in ranges.values()), default=0.0) if cards else 0.0
    lost = sum(1 for s in after if s.card is None)
    return Measure(
        take=take,
        frames=len(samples),
        from_s=from_s,
        window=window,
        first_seen=after[0].t if after else None,
        lost=lost,
        ranges=ranges,
        worst_edge_range=worst,
        contrast=(min(s.card.contrast for s in cards), max(s.card.contrast for s in cards)) if cards else None,
        motion=(moved[0], moved[-1]) if moved else None,
        changed_frames=len(moved),
        still=bool(cards) and lost == 0 and worst <= STILL_PT,
    )


def decode(video: Path, width: int, height: int) -> Iterator[np.ndarray]:
    """Every encoded frame in presentation order, as luminance at the video's own width x height."""
    size = width * height * 3
    # The rawvideo muxer logs every repeated dts at error level; a file keeps the pipe from filling.
    with tempfile.TemporaryFile() as errors:
        proc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-nostdin", "-i", str(video), "-fps_mode", "passthrough", "-f", "rawvideo",
             "-pix_fmt", "rgb24", "-"],
            stdout=subprocess.PIPE, stderr=errors,
        )
        try:
            while True:
                buf = proc.stdout.read(size)
                if len(buf) < size:
                    break
                yield np.frombuffer(buf, np.uint8).reshape(height, width, 3).mean(axis=2, dtype=np.float32)
        finally:
            proc.stdout.close()
            code = proc.wait()
        if code != 0:
            errors.seek(0)
            tail = errors.read().decode(errors="replace").strip().splitlines()[-3:]
            raise DecodeFailure(f"ffmpeg exited {code} decoding {video}: {' / '.join(tail)}")


def samples(video: Path, take: Take, x: float = 28, ref: float = 8) -> List[Sample]:
    try:
        times, _ = probe(video)
    except NoTake as error:
        raise DecodeFailure(str(error)) from None
    width, height = take.video_px
    px_per_pt = width / take.screen_pt[0]
    cards = [detect(lum, px_per_pt, x, ref) for lum in decode(video, width, height)]
    if len(cards) != len(times):
        raise DecodeFailure(f"ffmpeg decoded {len(cards)} frames of {video} and ffprobe timed {len(times)}")
    return [Sample(t, card) for t, card in zip(times, cards)]


def measure(video, from_s: Optional[float] = None, x: float = 28, ref: float = 8) -> Measure:
    video = Path(video)
    stamp = video.with_suffix(".take")
    try:
        take = parse(stamp.read_text())
    except OSError:
        raise Usage(f"no take stamp {stamp}; record the video with verify.sh record") from None
    except ValueError as error:
        raise Usage(f"{stamp}: {error}") from None
    if take.screen_pt is None:
        raise Usage(f"{stamp} has no screen_pt=, so its pixels cannot be read as points; record it again")
    found = samples(video, take, x, ref)
    if from_s is None:
        drive_start = take.drive_start if take.drive else 0.0
        from_s = full_size(found, drive_start) if take.drive.split()[:1] == ["launch"] else drive_start
    return summarize(take, found, from_s)


def full_size(found: Sequence[Sample], after: float) -> float:
    """When a launch's card takes, for good, its final width and nine tenths of its final contrast, read
    from the last SETTLED_FRAMES cards. iOS opens an app by scaling its window up from the icon, or fading
    it in from black when the app runs with -UITEST_DISABLE_ANIMATIONS, and until then the system, not the
    app, moves the card's edges; before the window opens, the springboard can read as a card of another
    width. One unsettled frame does not end the walk back, so a single stray frame cannot shrink the
    window to the frames after it; two in a row do."""
    cards = [s for s in found if s.card is not None and s.t >= after]
    if not cards:
        return after
    final = [s.card for s in cards[-SETTLED_FRAMES:]]
    counts = Counter(c.right - c.left for c in final)
    # A tie goes to the later width: a take can end on the last frames of the zoom.
    width = max(reversed([c.right - c.left for c in final]), key=lambda w: counts[w])
    contrast = median(c.contrast for c in final)
    settled = [s.card.right - s.card.left == width and s.card.contrast >= LAUNCH_CONTRAST * contrast for s in cards]
    for i in range(len(cards) - 1, 0, -1):
        if not settled[i] and not settled[i - 1]:
            return cards[min(i + 1, len(cards) - 1)].t
    return cards[0].t


def _span(lo: float, hi: float) -> str:
    return f"{lo:.1f}..{hi:.1f}"


def report(m: Measure) -> List[str]:
    lines = []
    if m.invalid:
        lines.append(f"INVALID take: {'; '.join(m.invalid)}")
    if m.take.animations != "on":
        lines.append(f"animations {m.take.animations}: this take cannot show motion")
    lines.append(f"take={'INVALID' if m.invalid else 'VALID'} animations={m.take.animations} frames={m.frames} "
                 f"window_frames={len(m.window)}")
    if m.first_seen is None:
        return lines
    lines.append(f"first_seen={m.first_seen:.3f} lost={m.lost}")
    lines.append(" ".join(f"{name}={_span(*m.ranges[name])}" for name in EDGES))
    lines.append(f"worst_edge_range={m.worst_edge_range:.1f}")
    lines.append(f"contrast={_span(*m.contrast)}")
    if m.motion is None:
        lines.append("motion=none")
    else:
        lines.append(f"motion={m.motion[0]:.3f}..{m.motion[1]:.3f} motion_ms={m.motion_ms} "
                     f"changed_frames={m.changed_frames}")
    lines.append(f"still={'yes' if m.still else 'no'}")
    return lines


def write_tsv(path: Path, m: Measure) -> None:
    drive_start = m.take.drive_start if m.take.drive else None
    rows = ["t\tt_from_drive\ttop\tbottom\tleft\tright\tcontrast"]
    for s in m.window:
        from_drive = "" if drive_start is None else f"{s.t - drive_start:.3f}"
        cells = [""] * 5 if s.card is None else [f"{s.card.edge(n):.1f}" for n in EDGES] + [f"{s.card.contrast:.1f}"]
        rows.append("\t".join([f"{s.t:.3f}", from_drive] + cells))
    path.write_text("\n".join(rows) + "\n")


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="cardframe.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("video", type=Path)
    parser.add_argument("--tsv", type=Path)
    parser.add_argument("--from", dest="from_s", type=float)
    parser.add_argument("--x", type=float, default=28)
    parser.add_argument("--ref", type=float, default=8)
    args = parser.parse_args(argv)
    try:
        m = measure(args.video, args.from_s, args.x, args.ref)
    except Usage as error:
        print(error, file=sys.stderr)
        return 2
    except DecodeFailure as error:
        print(error, file=sys.stderr)
        return 70
    print("\n".join(report(m)))
    if args.tsv:
        write_tsv(args.tsv, m)
    if m.first_seen is None:
        print(f"no card in any of the {len(m.window)} frames from {m.from_s:.3f} s", file=sys.stderr)
        return 1
    return 3 if m.invalid or m.take.animations != "on" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
