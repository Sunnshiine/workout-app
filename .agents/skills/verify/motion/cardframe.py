#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""The Active Set Card's edges, in points, in every encoded frame of a `verify.sh record` take.

  uv run .agents/skills/verify/motion/cardframe.py <run>/NAME.mp4 [--tsv PATH] [--from S] [--x 28] [--ref 8]

Reads NAME.take beside the video. Each encoded frame is decoded once and timed by its own presentation
time, in seconds after the take started. The window is the frames at or after --from, by default the
drive's end for a launch take (before it the springboard is on screen), else the drive's start, else 0.
The card is the longest vertical run, at least 120 pt with gaps up to 8 pt merged, where the column at
--x pt is brighter than the paper column at --ref pt by 4.0; left and right come from a row scan at the
run's middle. Frames before the card first shows are not lost; a frame after it without the card is.

Prints key=value lines:
  take=VALID animations=on frames=111 window_frames=110
  first_seen=0.917 lost=0
  top=402.5..476.0 bottom=618.5..692.0 left=12.0..12.0 right=402.0..402.0
  worst_edge_range=73.5
  contrast=14.8..15.3
  motion=2.783..3.560 motion_ms=777 changed_frames=24
  still=no
motion spans the first and last frame whose edges moved more than 0.75 pt from the previous frame with
the card (motion=none when none did). still=yes when the card was seen, never lost, and no edge ranged
over more than 0.5 pt. --tsv writes one row per window frame: t, t_from_drive, top, bottom, left, right,
contrast, blank cells for a frame with no card.

Exit 0 measured, 1 no card in any window frame, 3 measured but the take is INVALID or its animations are
not on (a banner line first), 2 usage or no readable NAME.take, 70 ffmpeg or ffprobe failed.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Sequence, Tuple

import numpy as np

PX_PER_PT = 2.0
THRESHOLD = 4.0
MIN_RUN_PT = 120.0
MERGE_GAP_PT = 8.0
STILL_PT = 0.5
STEP_PT = 0.75
EDGES = ("top", "bottom", "left", "right")


class Usage(Exception):
    pass


class DecodeFailure(Exception):
    pass


@dataclass(frozen=True)
class Take:
    """The fields of a take/1 stamp that measuring reads."""

    path: Path
    verdict: str
    invalid: str
    animations: str
    drive: str
    drive_start: Optional[float]
    drive_end: Optional[float]
    load_before: str
    load_after: str
    screen_pt: Tuple[int, int]
    video_px: Tuple[int, int]

    @property
    def default_from(self) -> float:
        if self.drive.split()[:1] == ["launch"] and self.drive_end is not None:
            return self.drive_end
        if self.drive and self.drive_start is not None:
            return self.drive_start
        return 0.0


def read_take(path: Path) -> Take:
    try:
        lines = path.read_text().splitlines()
    except OSError:
        raise Usage(f"no take stamp {path}; record the video with verify.sh record") from None
    fields = dict(line.split("=", 1) for line in lines if "=" in line)

    def field(key: str) -> str:
        if key not in fields:
            raise Usage(f"{path} has no {key}=")
        return fields[key]

    def seconds(key: str) -> Optional[float]:
        text = field(key)
        return float(text) if text else None

    def size(key: str) -> Tuple[int, int]:
        width, _, height = field(key).partition("x")
        try:
            return int(width), int(height)
        except ValueError:
            raise Usage(f"{path}: {key}={fields[key]} is not WxH") from None

    try:
        return Take(
            path=path,
            verdict=field("verdict"),
            invalid=field("invalid"),
            animations=field("animations"),
            drive=field("drive"),
            drive_start=seconds("drive_start"),
            drive_end=seconds("drive_end"),
            load_before=field("load_before"),
            load_after=field("load_after"),
            screen_pt=size("screen_pt"),
            video_px=size("video_px"),
        )
    except ValueError as error:
        raise Usage(f"{path}: {error}") from None


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


def _band(pt: float) -> slice:
    px = int(pt * PX_PER_PT)
    return slice(px - 2, px + 3)


def _runs(mask: np.ndarray) -> List[Tuple[int, int]]:
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
        if merged and run[0] - merged[-1][1] <= MERGE_GAP_PT * PX_PER_PT:
            merged[-1] = (merged[-1][0], run[1])
        else:
            merged.append(run)
    return merged


def detect(lum: np.ndarray, x_pt: float = 28, ref_pt: float = 8) -> Optional[Card]:
    """lum is a luminance image at PX_PER_PT."""
    card_band, paper_band = _band(x_pt), _band(ref_pt)
    contrast = lum[:, card_band].mean(axis=1) - lum[:, paper_band].mean(axis=1)
    runs = [r for r in _runs(contrast > THRESHOLD) if (r[1] - r[0]) / PX_PER_PT >= MIN_RUN_PT]
    if not runs:
        return None
    start, end = max(runs, key=lambda r: r[1] - r[0])
    middle = (start + end) // 2
    row = lum[max(0, middle - 2):middle + 3].mean(axis=0)
    on = np.where(row - row[paper_band].mean() > THRESHOLD)[0]
    left = on[0] / PX_PER_PT if len(on) else math.nan
    right = (on[-1] + 1) / PX_PER_PT if len(on) else math.nan
    return Card(
        top=start / PX_PER_PT,
        bottom=(end + 1) / PX_PER_PT,
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


def summarize(take: Take, samples: Sequence[Sample], from_s: float) -> Measure:
    window = tuple(s for s in samples if s.t >= from_s)
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


def frame_times(video: Path) -> List[float]:
    done = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "json",
         str(video)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    if done.returncode != 0:
        raise DecodeFailure(f"ffprobe could not read {video}: {done.stderr.strip()}")
    try:
        return sorted(float(frame["pts_time"]) for frame in json.loads(done.stdout).get("frames", []))
    except (KeyError, ValueError) as error:
        raise DecodeFailure(f"ffprobe gave a frame of {video} no time: {error}") from None


def decode(video: Path, width: int, height: int) -> Iterator[np.ndarray]:
    """Every encoded frame in presentation order, as luminance at width x height."""
    size = width * height * 3
    # The rawvideo muxer logs every repeated dts at error level; a file keeps the pipe from filling.
    with tempfile.TemporaryFile() as errors:
        proc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-nostdin", "-i", str(video), "-fps_mode", "passthrough",
             "-vf", f"scale={width}:{height}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
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
    times = frame_times(video)
    width = round(take.screen_pt[0] * PX_PER_PT)
    height = round(take.video_px[1] * width / take.video_px[0])
    cards = [detect(lum, x, ref) for lum in decode(video, width, height)]
    if len(cards) != len(times):
        raise DecodeFailure(f"ffmpeg decoded {len(cards)} frames of {video} and ffprobe timed {len(times)}")
    return [Sample(t, card) for t, card in zip(times, cards)]


def take_of(video: Path) -> Path:
    return video.with_suffix(".take")


def measure(video, from_s: Optional[float] = None, x: float = 28, ref: float = 8) -> Measure:
    video = Path(video)
    take = read_take(take_of(video))
    start = take.default_from if from_s is None else from_s
    return summarize(take, samples(video, take, x, ref), start)


def _span(lo: float, hi: float) -> str:
    return f"{lo:.1f}..{hi:.1f}"


def report(m: Measure) -> List[str]:
    lines = []
    if m.take.verdict != "VALID":
        lines.append(f"INVALID take: {m.take.invalid}")
    if m.take.animations != "on":
        lines.append(f"animations {m.take.animations}: this take cannot show motion")
    lines.append(f"take={m.take.verdict} animations={m.take.animations} frames={m.frames} "
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
    return 3 if m.take.verdict != "VALID" or m.take.animations != "on" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
