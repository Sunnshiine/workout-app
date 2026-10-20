"""The card cardframe.py reads from decoded frames: its thresholds, its types, and each step from a
frame's luminance to a Measure (detect, open_window, box_of, look_of, card_of, summarize)."""
from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, Iterable, List, Literal, NamedTuple, Optional, Sequence, Tuple, Union

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from take import RULES_THAT_ONLY_HIDE_MOTION, Reason, Take, judge  # noqa: E402
from tree import Frame  # noqa: E402

THRESHOLD = 4.0
MIN_RUN_PT = 120.0
MERGE_GAP_PT = 8.0
STILL_PT = 0.5
MIDDLE_PT = 8.0
HEIGHT_PT = 24.0
EDGES = ("top", "bottom", "left", "right")

CELL_PT = 4.0
GRID = (24, 12)
TILE_LUM = 0.5
RAMP_FRAC = 0.75
BLACK_LUM = 2.0
FADE_S = 0.5
SOLID_CONTRAST = 0.75
LOOK_LUM = 0.5
MIN_WINDOW_S = 1.5

HIDES_MOTION = RULES_THAT_ONLY_HIDE_MOTION | {"window"}


def moved_counts(rules: Iterable[str]) -> bool:
    return set(rules) <= HIDES_MOTION


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


@dataclass(frozen=True)
class NoCard:
    why: str


class Still(Enum):
    YES = "yes"
    NO = "no"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class Measure:
    take: Take
    samples: Tuple[Sample, ...]
    window: Window
    card: Union[Seen, NoCard]
    invalid: Tuple[Reason, ...]

    @property
    def frames(self) -> int:
        return len(self.samples)

    @property
    def in_window(self) -> Tuple[Sample, ...]:
        return self.samples[self.window.start:]

    @property
    def unvouched(self) -> Optional[str]:
        box = self.card.box if isinstance(self.card, Seen) else None
        if box is not None and box.partial:
            first = (f"was faint for its first {box.faint} frames" if box.faint
                     else "was missing from the window's first frames")
            return f"the card {first}, so its edges were not read from the window's start"
        if self.invalid:
            return f"take INVALID: {'; '.join(r.text for r in self.invalid)}"
        if self.take.animations != "on":
            return f"animations {self.take.animations}"
        return None

    @property
    def still(self) -> Still:
        if isinstance(self.card, NoCard):
            return Still.UNKNOWN
        if self.card.box.changed or self.card.look.kind is LookKind.CHANGED:
            return Still.NO if moved_counts(r.rule for r in self.invalid) else Still.UNKNOWN
        return Still.YES if self.unvouched is None else Still.UNKNOWN


def _band(pt: float, px_per_pt: float) -> slice:
    px = int(pt * px_per_pt)
    return slice(px - 2, px + 3)


def _runs(mask: np.ndarray, px_per_pt: float, height_pt: float) -> List[Tuple[int, int]]:
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
        if (merged and run[0] - merged[-1][1] <= MERGE_GAP_PT * px_per_pt
                and (run[1] + 1 - merged[-1][0]) / px_per_pt <= height_pt):
            merged[-1] = (merged[-1][0], run[1])
        else:
            merged.append(run)
    return merged


def box_cells(card: Card) -> Tuple[slice, slice]:
    return (slice(math.ceil(card.top / CELL_PT), math.floor(card.bottom / CELL_PT)),
            slice(math.ceil(card.left / CELL_PT), math.floor(card.right / CELL_PT)))


def detect(lum: np.ndarray, px_per_pt: float, height_pt: float, x_pt: float = 28, ref_pt: float = 8) -> Optional[Card]:
    card_band, paper_band = _band(x_pt, px_per_pt), _band(ref_pt, px_per_pt)
    contrast = lum[:, card_band].mean(axis=1) - lum[:, paper_band].mean(axis=1)
    runs = [r for r in _runs(contrast > THRESHOLD, px_per_pt, height_pt) if (r[1] - r[0]) / px_per_pt >= MIN_RUN_PT]
    if not runs:
        return None
    start, end = max(runs, key=lambda r: r[1] - r[0])
    middle = (start + end) // 2
    row = lum[max(0, middle - 2):middle + 3].mean(axis=0)
    on = np.where(row - row[paper_band].mean() > THRESHOLD)[0]
    if not len(on):
        return None
    card = Card(
        top=start / px_per_pt,
        bottom=(end + 1) / px_per_pt,
        left=float(on[0] / px_per_pt),
        right=float((on[-1] + 1) / px_per_pt),
        contrast=float(contrast[start:end + 1].mean()),
    )
    rows, cols = box_cells(card)
    return card if rows.start < rows.stop and cols.start < cols.stop else None


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


class Fade(NamedTuple):
    last: int
    later: Optional[int]


def launch_fade(samples: Sequence[Sample], after: float) -> Optional[Fade]:
    changes = screen_changes(samples)
    first = next((i for i in range(1, len(samples)) if samples[i].t >= after), len(samples))
    start = next((i for i in range(first, len(samples))
                  if changes[i] >= RAMP_FRAC and samples[i - 1].cells.mean() < BLACK_LUM), None)
    if start is None:
        return None
    last = max(i for i in range(start, len(samples))
               if changes[i] >= RAMP_FRAC and samples[i].t <= samples[start].t + FADE_S)
    return Fade(last, next((i for i in range(last + 1, len(samples)) if changes[i] >= RAMP_FRAC), None))


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
            fade = launch_fade(samples, take.drive_start)
            if fade is None:
                reasons.append(Reason("ramp", "no frame after the launch began changed three quarters of the screen, "
                                              "so iOS's fade-in cannot be told from the app's motion"))
            else:
                opened, start, at = Opened.RAMP, fade.last, samples[fade.last].t
                if fade.later is not None:
                    reasons.append(Reason("screen", "a frame at +%.3f s changed three quarters of the screen after "
                                                    "iOS's fade-in ended, so the card cannot be read through it"
                                          % samples[fade.later].t))
    seconds = take.stopped - at
    if seconds < MIN_WINDOW_S:
        reasons.append(Reason("window", "the window watched %.2f s from +%.3f s, under %g s"
                              % (seconds, at, MIN_WINDOW_S)))
    return Window(opened, start, at, seconds), tuple(reasons)


def _apart(a: Card, b: Card) -> bool:
    return any(abs(a.edge(n) - b.edge(n)) > STILL_PT for n in EDGES)


def box_of(window: Sequence[Sample], settled: Card) -> Box:
    seen = next(i for i, s in enumerate(window)
                if s.card is not None and s.card.contrast >= SOLID_CONTRAST * settled.contrast)
    after = window[seen:]
    shown = [s for s in after if s.card is not None]
    cards = [s.card for s in shown]
    ranges = {}
    for name in EDGES:
        values = [c.edge(name) for c in cards]
        ranges[name] = (min(values), max(values))
    settle = next(k for k in range(len(cards)) if not any(_apart(c, settled) for c in cards[k:]))
    depart = next((k for k in range(settle) if _apart(cards[k], cards[0])), settle)
    return Box(
        first_seen=window[seen].t,
        partial=seen > 0,
        lost=len(after) - len(cards),
        faint=sum(1 for s in window[:seen] if s.card is not None),
        ranges=ranges,
        worst_edge_range=max(hi - lo for lo, hi in ranges.values()),
        contrast=(min(c.contrast for c in cards), max(c.contrast for c in cards)),
        motion=None if settle == 0 else (shown[depart].t, shown[settle].t),
        changed_frames=sum(1 for a, b in zip(cards, cards[1:]) if _apart(a, b)),
    )


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


def _fits(settled: Card, card_pt: Frame, tree_holds_destination: bool) -> bool:
    x, y = card_pt.center
    return (abs(settled.bottom - settled.top - card_pt.height) <= HEIGHT_PT
            and abs((settled.left + settled.right) / 2 - x) <= MIDDLE_PT
            and (tree_holds_destination or abs((settled.top + settled.bottom) / 2 - y) <= MIDDLE_PT))


def card_of(card_pt: Union[Frame, Literal["none"]], window: Sequence[Sample], at: float) -> Union[Seen, NoCard]:
    if card_pt == "none":
        return NoCard("the accessibility tree held no active-set-card when the recorder stopped")
    last = next((s for s in reversed(window) if s.card is not None), None)
    if last is None:
        return NoCard(f"none of the {len(window)} frames from {at:.3f} s showed it")
    settled = last.card
    box = box_of(window, settled)
    still_moving_at_stop = box.motion is not None and box.motion[1] == last.t
    if not _fits(settled, card_pt, tree_holds_destination=still_moving_at_stop):
        return NoCard(f"the box read last, {_span(settled.top, settled.bottom)} {_span(settled.left, settled.right)}, "
                      f"is not where the accessibility tree put active-set-card, {card_pt.text}")
    return Seen(box, look_of(window, settled))


def summarize(take: Take, samples: Sequence[Sample], from_s: Optional[float] = None) -> Measure:
    window, reasons = open_window(take, samples, from_s)
    card = card_of(take.card_pt, samples[window.start:], window.at)
    return Measure(take, tuple(samples), window, card, tuple(judge(take)) + reasons)


def _span(lo: float, hi: float) -> str:
    return f"{lo:.1f}..{hi:.1f}"
