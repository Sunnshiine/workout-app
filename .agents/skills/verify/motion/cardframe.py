#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""The Active Set Card in every encoded frame of a `verify.sh record` take: where its box was, and how the
look inside that box changed.

  uv run .agents/skills/verify/motion/cardframe.py <run>/NAME.mp4 [--tsv PATH] [--from S] [--x 28] [--ref 8]

Reads NAME.take beside the video. Each encoded frame is decoded once, at the recording's own pixels
(video width over the stamp's screen_pt width per point), and timed by its own presentation time, in
seconds after the take started. recordVideo writes a frame only when the screen changes, so a still
screen is one frame and a window is a span of time: the frame showing when it opens, every frame after
it, and the still screen up to the moment the recorder stopped.

Window. It opens at --from S, else at the drive's start, else at 0. A launch take opens it at the last
frame of iOS's launch fade: the last frame, after the drive began, in which at least three quarters of
the screen changed from the frame before (24 x 12 tiles, each changed by more than 0.5 of mean luminance).
Every recorded launch, animations on or off, fades the app in from black that way, and no app motion
recorded changed more than 0.69 of the screen. The window is INVALID when:
  - a launch take has no such frame (rule ramp), because then the window holds the system's fade;
  - it watched less than the take's tail, from opening to the recorder's stop (rule window), as when the
    fade ended after the launch returned. A tap's window opens at the drive's start and always watches
    its tail.
A take is also INVALID for the stamp's own reasons (load, recorder, coverage; see take.py summary).

Box. The card is the longest vertical run, at least 120 pt with gaps up to 8 pt merged, where the column
at --x pt is brighter than the paper column at --ref pt by 4.0; left and right come from a row scan at the
run's middle, and a run whose middle row shows nothing brighter than the paper is no card. The settled
card is the window's last. The box is read from the first solid card: the first detection with at least
three quarters of the settled card's contrast. Detections before it are faint and their edges are not
read, because a faint card reads short and narrow. edges=partial when the first solid card is not the
window's first frame. After it every detection counts, at any contrast, and a frame without the card is
lost.

Look. In 4 pt cells wholly inside the settled card's box, d is each window frame's mean luminance
difference from the window's last frame, so the last frame's d is 0 and look_peak is the largest d. The
look changed when look_peak is over 0.5. look_motion ends at the first frame from which d stays at or
under 0.5, and starts at the first frame before that whose d differs from the window's first d by more
than 0.5, else at the same frame. look=cut when it starts and ends on one frame (look_ms=0): the content
inside a still box swapped in one frame, as a label does, which is not motion. look=changed when it took
longer, as a fade in place, a slide, or a fly-in does. look_frames counts the frames whose cells differ
from the frame before by more than 0.5. The look sees only the settled box, so it reports that a card
changed, not where it went.

Prints key=value lines:
  take=VALID animations=on frames=212 window_frames=87
  window=ramp from=3.948 to=7.320 window_s=3.372
  first_seen=5.048 lost=0 faint=0 edges=partial
  top=481.3..497.3 bottom=762.3..777.3 left=16.0..26.3 right=386.0..396.3
  worst_edge_range=16.0
  contrast=12.2..13.0
  motion=5.065..5.148 motion_ms=83 changed_frames=6
  look_peak=43.3 look_frames=75 look_motion=4.000..5.198 look_ms=1198
  still=no box=changed look=changed
window= is how it opened (ramp, drive, start or from), from= and to= its span, and window_s how long it
watched. first_seen is the first solid card, lost the frames after it without the card, faint the
detections before it. Each edge's range and worst_edge_range are over the cards from first_seen on.
motion spans the first and last of those cards whose edges moved more than 0.75 pt from the card before
(motion=none when none did). box=changed when the card was lost or an edge ranged over 0.5 pt. still=no
when the box changed or look=changed; else unknown when the take is INVALID for any reason, because an
INVALID take cannot vouch for stillness; else yes. A cut does not make still=no. --tsv writes one row per
window frame: t, t_from_drive, top, bottom, left, right, contrast, look (the frame's d), screen (the
fraction of tiles that changed from the frame before); blank card cells for a frame with no card, blank
screen on the take's first frame.

It cannot see:
  - first-appear motion that ends inside iOS's launch fade, or the part of it that ran under the fade;
  - where a card went before its first solid frame, or while its left edge was right of --x: a fade, a
    slide from the side, or a fly-in shows in the edges only from then (edges=partial), and in the look;
  - motion still running when the recorder stopped: its range and look_motion are truncated;
  - a change inside the box under 0.5 of mean luminance, or anything outside the settled box;
  - two cuts, or a one-frame flash, in one window: they read as one look=changed spanning both;
  - a card that pops in with no animation inside the window: it reads look=cut;
  - an app change over three quarters of the screen in one frame after a launch: it reads as the fade's
    end.

Exit 0 measured, 1 no card in any window frame, 3 measured but INVALID or animations not on (a banner line
first), 2 usage, no readable NAME.take with a screen_pt=, or pixels per point that do not tile 4 pt cells,
70 ffmpeg or ffprobe failed.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Sequence, Tuple

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from take import RULES_THAT_ONLY_HIDE_MOTION, NoTake, Reason, Take, judge, parse, probe  # noqa: E402

THRESHOLD = 4.0
MIN_RUN_PT = 120.0
MERGE_GAP_PT = 8.0
STILL_PT = 0.5
STEP_PT = 0.75
EDGES = ("top", "bottom", "left", "right")

CELL_PT = 4.0
GRID = (24, 12)
TILE_LUM = 0.5
RAMP_FRAC = 0.75
SOLID_CONTRAST = 0.75
LOOK_LUM = 0.5

HIDES_MOTION = RULES_THAT_ONLY_HIDE_MOTION | {"window"}


class Usage(Exception):
    pass


class DecodeFailure(Exception):
    pass


@dataclass(frozen=True)
class Card:
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
    cells: np.ndarray


class Opened(Enum):
    START = "start"
    DRIVE = "drive"
    RAMP = "ramp"
    FROM = "from"


@dataclass(frozen=True)
class Window:
    opened: Opened
    start: int
    at: float
    seconds: float


@dataclass(frozen=True)
class Box:
    first_seen: float
    partial: bool
    lost: int
    faint: int
    ranges: Dict[str, Tuple[float, float]]
    worst_edge_range: float
    contrast: Tuple[float, float]
    motion: Optional[Tuple[float, float]]
    changed_frames: int

    @property
    def changed(self) -> bool:
        return self.lost > 0 or self.worst_edge_range > STILL_PT

    @property
    def motion_ms(self) -> Optional[int]:
        return None if self.motion is None else round((self.motion[1] - self.motion[0]) * 1000)


class LookKind(Enum):
    STILL = "still"
    CUT = "cut"
    CHANGED = "changed"


@dataclass(frozen=True)
class Look:
    from_settled: Tuple[float, ...]
    frames: int
    motion: Optional[Tuple[float, float]]

    @property
    def peak(self) -> float:
        return max(self.from_settled)

    @property
    def kind(self) -> LookKind:
        if self.motion is None:
            return LookKind.STILL
        return LookKind.CUT if self.motion[0] == self.motion[1] else LookKind.CHANGED

    @property
    def ms(self) -> Optional[int]:
        return None if self.motion is None else round((self.motion[1] - self.motion[0]) * 1000)


@dataclass(frozen=True)
class Seen:
    box: Box
    look: Look


class Still(Enum):
    YES = "yes"
    NO = "no"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class Measure:
    take: Take
    samples: Tuple[Sample, ...]
    window: Window
    card: Optional[Seen]
    invalid: Tuple[Reason, ...]

    @property
    def frames(self) -> int:
        return len(self.samples)

    @property
    def in_window(self) -> Tuple[Sample, ...]:
        return self.samples[self.window.start:]

    @property
    def still(self) -> Still:
        if self.card is None:
            return Still.UNKNOWN
        if self.card.box.changed or self.card.look.kind is LookKind.CHANGED:
            return Still.NO
        return Still.UNKNOWN if self.invalid else Still.YES


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
    if not len(on):
        return None
    return Card(
        top=start / px_per_pt,
        bottom=(end + 1) / px_per_pt,
        left=float(on[0] / px_per_pt),
        right=float((on[-1] + 1) / px_per_pt),
        contrast=float(contrast[start:end + 1].mean()),
    )


def cells_of(lum: np.ndarray, px_per_pt: float) -> np.ndarray:
    c = round(CELL_PT * px_per_pt)
    rows, cols = lum.shape[0] // c, lum.shape[1] // c
    return lum[:rows * c, :cols * c].reshape(rows, c, cols, c).mean(axis=(1, 3), dtype=np.float32)


def _tiles(cells: np.ndarray) -> np.ndarray:
    r, c = cells.shape[0] // GRID[0], cells.shape[1] // GRID[1]
    return cells[:r * GRID[0], :c * GRID[1]].reshape(GRID[0], r, GRID[1], c).mean(axis=(1, 3))


def changed_fraction(before: np.ndarray, after: np.ndarray) -> float:
    return float((np.abs(_tiles(after) - _tiles(before)) > TILE_LUM).mean())


def screen_changes(samples: Sequence[Sample]) -> List[Optional[float]]:
    return [None] + [changed_fraction(a.cells, b.cells) for a, b in zip(samples, samples[1:])]


def last_ramp_frame(samples: Sequence[Sample], after: float) -> Optional[int]:
    changes = screen_changes(samples)
    return max((i for i in range(1, len(samples)) if samples[i].t >= after and changes[i] >= RAMP_FRAC),
               default=None)


def _showing(samples: Sequence[Sample], at: float) -> int:
    return max((i for i, s in enumerate(samples) if s.t <= at), default=0)


def open_window(take: Take, samples: Sequence[Sample], from_s: Optional[float]) -> Tuple[Window, Tuple[Reason, ...]]:
    reasons: List[Reason] = []
    if from_s is not None:
        opened, start, at = Opened.FROM, _showing(samples, from_s), from_s
    elif not take.drive:
        opened, start, at = Opened.START, 0, 0.0
    else:
        opened, start, at = Opened.DRIVE, _showing(samples, take.drive_start), take.drive_start
        if take.drive.split()[:1] == ["launch"]:
            last = last_ramp_frame(samples, take.drive_start)
            if last is None:
                reasons.append(Reason("ramp", "no frame after the launch began changed three quarters of the screen, "
                                              "so iOS's fade-in cannot be told from the app's motion"))
            else:
                opened, start, at = Opened.RAMP, last, samples[last].t
    seconds = take.stopped - at
    if seconds < take.tail:
        reasons.append(Reason("window", "the window watched %.2f s from +%.3f s, under the %g s tail"
                              % (seconds, at, take.tail)))
    return Window(opened, start, at, seconds), tuple(reasons)


def box_of(window: Sequence[Sample], settled: Card) -> Box:
    seen = next(i for i, s in enumerate(window)
                if s.card is not None and s.card.contrast >= SOLID_CONTRAST * settled.contrast)
    after = window[seen:]
    shown = [s for s in after if s.card is not None]
    cards = [s.card for s in shown]
    ranges = {}
    for name in EDGES:
        values = [c.edge(name) for c in cards]
        ranges[name] = (float(np.nanmin(values)), float(np.nanmax(values)))
    moved = [b.t for a, b in zip(shown, shown[1:])
             if any(abs(a.card.edge(n) - b.card.edge(n)) > STEP_PT for n in EDGES)]
    return Box(
        first_seen=window[seen].t,
        partial=seen > 0,
        lost=len(after) - len(cards),
        faint=sum(1 for s in window[:seen] if s.card is not None),
        ranges=ranges,
        worst_edge_range=max(hi - lo for lo, hi in ranges.values()),
        contrast=(min(c.contrast for c in cards), max(c.contrast for c in cards)),
        motion=(moved[0], moved[-1]) if moved else None,
        changed_frames=len(moved),
    )


def box_cells(card: Card) -> Tuple[slice, slice]:
    return (slice(math.ceil(card.top / CELL_PT), math.floor(card.bottom / CELL_PT)),
            slice(math.ceil(card.left / CELL_PT), math.floor(card.right / CELL_PT)))


def look_of(window: Sequence[Sample], settled: Card) -> Look:
    box = box_cells(settled)
    looks = [s.cells[box] for s in window]
    d = tuple(float(np.abs(look - looks[-1]).mean()) for look in looks)
    frames = sum(1 for a, b in zip(looks, looks[1:]) if float(np.abs(b - a).mean()) > LOOK_LUM)
    if max(d) <= LOOK_LUM:
        return Look(d, frames, None)
    settle = next(k for k in range(len(d)) if max(d[k:]) <= LOOK_LUM)
    depart = next((k for k in range(settle) if abs(d[k] - d[0]) > LOOK_LUM), settle)
    return Look(d, frames, (window[depart].t, window[settle].t))


def summarize(take: Take, samples: Sequence[Sample], from_s: Optional[float] = None) -> Measure:
    window, reasons = open_window(take, samples, from_s)
    frames = samples[window.start:]
    settled = next((s.card for s in reversed(frames) if s.card is not None), None)
    card = None if settled is None else Seen(box_of(frames, settled), look_of(frames, settled))
    return Measure(take, tuple(samples), window, card, tuple(judge(take)) + reasons)


def decode(video: Path, width: int, height: int) -> Iterator[np.ndarray]:
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
    found = [Sample(t, detect(lum, px_per_pt, x, ref), cells_of(lum, px_per_pt))
             for t, lum in zip(times, decode(video, width, height))]
    if len(found) != len(times):
        raise DecodeFailure(f"ffmpeg decoded {len(found)} frames of {video} and ffprobe timed {len(times)}")
    return found


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
    px_per_pt = take.video_px[0] / take.screen_pt[0]
    if not (CELL_PT * px_per_pt).is_integer():
        raise Usage(f"{stamp}: {px_per_pt:g} px per point does not tile {CELL_PT:g} pt cells")
    return summarize(take, samples(video, take, x, ref), from_s)


def _span(lo: float, hi: float) -> str:
    return f"{lo:.1f}..{hi:.1f}"


def report(m: Measure) -> List[str]:
    lines = []
    if m.invalid:
        lines.append(f"INVALID take: {'; '.join(r.text for r in m.invalid)}")
    if m.take.animations != "on":
        lines.append(f"animations {m.take.animations}: this take cannot show motion")
    lines.append(f"take={'INVALID' if m.invalid else 'VALID'} animations={m.take.animations} frames={m.frames} "
                 f"window_frames={len(m.in_window)}")
    w = m.window
    lines.append(f"window={w.opened.value} from={w.at:.3f} to={m.take.stopped:.3f} window_s={w.seconds:.3f}")
    if m.card is None:
        return lines
    b, look = m.card.box, m.card.look
    lines.append(f"first_seen={b.first_seen:.3f} lost={b.lost} faint={b.faint} "
                 f"edges={'partial' if b.partial else 'full'}")
    lines.append(" ".join(f"{name}={_span(*b.ranges[name])}" for name in EDGES))
    lines.append(f"worst_edge_range={b.worst_edge_range:.1f}")
    lines.append(f"contrast={_span(*b.contrast)}")
    if b.motion is None:
        lines.append("motion=none")
    else:
        lines.append(f"motion={b.motion[0]:.3f}..{b.motion[1]:.3f} motion_ms={b.motion_ms} "
                     f"changed_frames={b.changed_frames}")
    lines.append(f"look_peak={look.peak:.1f} look_frames={look.frames}" + (
        "" if look.motion is None else
        f" look_motion={look.motion[0]:.3f}..{look.motion[1]:.3f} look_ms={look.ms}"))
    lines.append(f"still={m.still.value} box={'changed' if b.changed else 'still'} look={look.kind.value}")
    return lines


def write_tsv(path: Path, m: Measure) -> None:
    drive_start = m.take.drive_start if m.take.drive else None
    screen = screen_changes(m.samples)[m.window.start:]
    looks = m.card.look.from_settled if m.card else [None] * len(m.in_window)
    rows = ["t\tt_from_drive\ttop\tbottom\tleft\tright\tcontrast\tlook\tscreen"]
    for s, d, changed in zip(m.in_window, looks, screen):
        from_drive = "" if drive_start is None else f"{s.t - drive_start:.3f}"
        cells = [""] * 5 if s.card is None else [f"{s.card.edge(n):.1f}" for n in EDGES] + [f"{s.card.contrast:.1f}"]
        rows.append("\t".join([f"{s.t:.3f}", from_drive] + cells + ["" if d is None else f"{d:.1f}",
                                                                     "" if changed is None else f"{changed:.3f}"]))
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
    if m.card is None:
        print(f"no card in any of the {len(m.in_window)} frames from {m.window.at:.3f} s", file=sys.stderr)
        return 1
    return 3 if m.invalid or m.take.animations != "on" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
