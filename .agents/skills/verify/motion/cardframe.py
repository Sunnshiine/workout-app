#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""The Active Set Card in every encoded frame of a `verify.sh record` take: where its box was, and how the
look inside that box changed.

  uv run .agents/skills/verify/motion/cardframe.py <run>/NAME.mp4 [--tsv PATH] [--from S] [--x 28] [--ref 8]

Reads NAME.take beside the video, whose card_pt= is the card's frame in the accessibility tree when the
recorder stopped, or none when the tree held no active-set-card; record keeps no take whose tree it
could not read. Each encoded frame is decoded once, at the recording's own pixels (video width over the
stamp's screen_pt width per point), and timed by its own presentation time, in seconds after the take
started. recordVideo writes a frame only when the screen changes, so a still screen is one frame and a
window is a span of time: the frame showing when it opens, every frame after it, and the still screen up
to the moment the recorder stopped.

Window. It opens at --from S, else at the drive's start, else at 0. --from on a launch take skips the
fade rules below, so a --from inside the fade reads the fade as motion. A launch take's window opens at the
end of iOS's fade-in, the full-screen frames in the 0.5 s after the screen leaves black; any later frame
that changes three quarters of the screen makes the take INVALID. The fade starts at the first frame after
the drive began that changed at least three quarters of the screen from the frame before (24 x 12 tiles,
each changed by more than 0.5 of mean luminance) and follows a frame darker than mean luminance 2.0. The
window opens at the last frame within 0.5 s of that start that changed three quarters of the screen;
frames between that changed less, as a repeated frame or the app's own motion does, are part of the fade.
Every recorded launch, animations on or off, fades the springboard out over the whole screen, holds black,
then fades the app in from black. The window is INVALID when:
  - a launch take has no frame where such a fade starts (rule ramp), because then the window holds the system's fade;
  - a frame after a launch's fade changed three quarters of the screen (rule screen), as a dim does,
    because the card cannot be read through it;
  - it watched less than 1.5 s, from opening to the recorder's stop (rule window), as when the fade ended
    long after the launch returned. A tap's window opens at the drive's start and watches the whole tail.
A take is also INVALID for the stamp's own reasons (load, recorder, coverage; see take.py summary).

Box. The card is the longest vertical run of at least 120 pt where the column at --x pt is brighter than
the paper column at --ref pt by 4.0. Runs join across a gap of up to 8 pt only while the joined run stays
no taller than card_pt=, so a neighbour touching the card, such as the rest pill, joins it only while the
pair fits that height. An unbroken run is the card at any height, so a card that shrinks to card_pt=
during the take reads its whole range. left and right come from a row scan at the run's middle. A run
whose middle row shows nothing brighter than the paper, or whose box holds no whole 4 pt cell, is no card.
The settled card is the last card the window shows. There is no card at all when card_pt=none, when no
window frame shows one, or when the settled card's height is more than 24 pt from card_pt='s or its middle
more than 8 pt from card_pt='s in x or y, as when a sheet over the session shows a section where the tree
still holds the card behind it. A card still moving in its last frame is checked for height and x only:
the tree is read after the recorder stops, so it holds where that card was going, and the move reads
still=no with its range truncated. The box is read from the first solid card: the first detection with at
least three quarters of the settled card's contrast. Detections before it are faint and their edges are not
read, because a faint card reads short and narrow. edges=partial when the first solid card is not the
window's first frame. After it every detection counts, at any contrast, and a frame without the card is
lost.

Look. In 4 pt cells wholly inside the settled card's box, d is each window frame's mean luminance
difference from the window's last frame, card or not, so the last frame's d is 0 and look_peak is the
largest d. The look changed when look_peak is over 0.5. look_motion ends at the first frame from which d
stays at or under 0.5, and starts at the first frame before that whose d differs from the window's first
d by more than 0.5, else at the same frame. look=cut when it starts and ends on one frame (look_ms=0):
the content inside a still box swapped in one frame, as a label does, which is not motion. look=changed
when it took longer, as a fade in place, a slide, or a fly-in does. look_frames counts the frames whose
cells differ from the frame before by more than 0.5. The look sees only the settled box, so it reports
that a card changed, not where it went.

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
motion runs from the first of those cards more than 0.5 pt from the first solid card on any edge to the
first card from which every later card stays within 0.5 pt of the settled one on every edge (motion=none
when the first solid card already did), so an eased move is timed from its first half point to its last.
changed_frames counts the cards more than 0.5 pt from the card before. box=changed when the card was lost
or an edge ranged over 0.5 pt. still=no when the box changed or look=changed and every INVALID rule only
hides motion (load, window). Animations off also only hides motion, so a move seen there reads no.
still=yes when nothing moved on a card where the tree puts it, the take is VALID, animations are on, and
edges=full. Else still=unknown: a move on a take INVALID for any other rule (ramp, screen, recorder,
coverage), which cannot vouch for it; nothing moved on a take that is INVALID, has animations off, or
has partial edges, any of which can hide motion; or no card. cardstill.py judges a take by the same rule.
A cut does not make still=no. --tsv writes one row per
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
  - an app change over three quarters of the screen within 0.5 s of the fade's start: it reads as the fade.

Exit 0 measured, 1 no card (`no card: <why>` on stderr), 3 measured but INVALID or animations not on (a
banner line first), 2 usage, no readable NAME.take with a screen_pt= and a card_pt=, or pixels per point
that do not tile 4 pt cells, 70 ffmpeg or ffprobe failed.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterator, List, Optional, Sequence

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from take import NoTake, Take, parse, probe  # noqa: E402
from cardread import *  # noqa: E402,F401,F403
from cardread import _span  # noqa: E402

class Usage(Exception):
    pass


class DecodeFailure(Exception):
    pass


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
    found = [Sample(t, None if take.card_pt == "none" else detect(lum, px_per_pt, take.card_pt.height, x, ref),
                    cells_of(lum, px_per_pt))
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
    if take.card_pt is None:
        raise Usage(f"{stamp} has no card_pt=, so the card's frame in the accessibility tree is unknown; "
                    "record it again")
    px_per_pt = take.video_px[0] / take.screen_pt[0]
    if not (CELL_PT * px_per_pt).is_integer():
        raise Usage(f"{stamp}: {px_per_pt:g} px per point does not tile {CELL_PT:g} pt cells")
    return summarize(take, samples(video, take, x, ref), from_s)


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
    if isinstance(m.card, NoCard):
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
    looks = m.card.look.from_settled if isinstance(m.card, Seen) else [None] * len(m.in_window)
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
    if isinstance(m.card, NoCard):
        print(f"no card: {m.card.why}", file=sys.stderr)
        return 1
    return 3 if m.invalid or m.take.animations != "on" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
