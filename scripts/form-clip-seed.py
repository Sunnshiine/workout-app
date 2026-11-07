#!/usr/bin/env python3
"""Writes a synthetic Form Clip: a side-on plate on a figure doing reps, labelled as synthetic.

The simulator has no camera, so this is the footage `xcrun simctl addmedia` seeds and the picker
imports. A JSON sidecar beside the movie holds the plate's true center per frame, top-left origin
and normalized to the displayed frame, so a tracker's path can be scored against it.

    uv run python3 scripts/form-clip-seed.py /tmp/clip.mp4 --reps 3 --drift 0.03
    uv run python3 scripts/form-clip-seed.py /tmp/rotated.mp4 --rotation 90
    uv run python3 scripts/form-clip-seed.py /tmp/lost.mp4 --lost-at 4.3
"""

import argparse
import json
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/SFNS.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def plate_center(args, t):
    """A rep starts at the top, goes down, and comes back, with the bar drifting forward at the bottom."""
    lifting = max(t - args.lead_in, 0)
    depth = (1 - math.cos(2 * math.pi * lifting * args.reps / (args.duration - args.lead_in))) / 2
    x = args.bar_x + args.drift * depth
    y = 0.30 + args.travel * depth
    return x, y, depth


def draw_frame(args, t, size, label_font):
    width, height = size
    cx, cy, depth = plate_center(args, t)
    frame = Image.new("RGB", size, (214, 218, 206))
    draw = ImageDraw.Draw(frame)
    if args.lost_at is not None and t >= args.lost_at:
        draw.rectangle([0, height - 64, width, height], fill=(32, 34, 36))
        draw.text((24, height - 50), args.label, fill=(240, 240, 230), font=label_font)
        return frame
    floor = int(height * 0.86)
    draw.rectangle([0, floor, width, height], fill=(150, 152, 142))
    draw.rectangle([int(width * 0.86), int(height * 0.18), int(width * 0.89), floor], fill=(70, 74, 70))

    bar = (cx * width, cy * height)
    hip = (bar[0] - 0.13 * width, cy * height + 0.06 * height + 0.12 * height * (1 - depth))
    knee = (bar[0] + 0.05 * width + 0.05 * width * depth, floor - 0.20 * height)
    ankle = (bar[0] - 0.02 * width, floor)
    head = (bar[0] - 0.02 * width, bar[1] - 0.065 * height)
    limb = int(width * 0.06)
    for start, end in ((bar, hip), (hip, knee), (knee, ankle)):
        draw.line([start, end], fill=(92, 104, 98), width=limb)
    radius_head = 0.035 * width
    draw.ellipse(
        [head[0] - radius_head, head[1] - radius_head, head[0] + radius_head, head[1] + radius_head],
        fill=(92, 104, 98),
    )

    outer = 0.15 * width
    rings = ((outer, (32, 34, 36)), (outer * 0.78, (58, 62, 66)), (outer * 0.55, (32, 34, 36)), (outer * 0.3, (196, 198, 192)))
    for radius, color in rings:
        draw.ellipse([bar[0] - radius, bar[1] - radius, bar[0] + radius, bar[1] + radius], fill=color)
    for spoke in range(8):
        angle = spoke * math.pi / 4
        r = outer * 0.66
        x, y = bar[0] + r * math.cos(angle), bar[1] + r * math.sin(angle)
        draw.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(214, 218, 206))
    hub = outer * 0.12
    draw.ellipse([bar[0] - hub, bar[1] - hub, bar[0] + hub, bar[1] + hub], fill=(40, 42, 44))

    label = args.label
    draw.rectangle([0, height - 64, width, height], fill=(32, 34, 36))
    draw.text((24, height - 50), label, fill=(240, 240, 230), font=label_font)
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument("--duration", type=float, default=9.0)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--reps", type=int, default=3)
    parser.add_argument("--bar-x", type=float, default=0.46)
    parser.add_argument("--travel", type=float, default=0.28)
    parser.add_argument("--drift", type=float, default=0.03)
    parser.add_argument("--lead-in", type=float, default=0.0, help="seconds the figure stands still before the first rep")
    parser.add_argument("--lost-at", type=float, default=None, help="seconds in at which the figure leaves the frame, as a walk-in would hide the plate")
    parser.add_argument("--rotation", type=int, default=0, choices=(0, 90, 180, 270), help="display rotation in the movie's metadata")
    parser.add_argument("--label", default="SYNTHETIC TEST CLIP")
    args = parser.parse_args()

    size = (720, 1280)
    label_font = font(30)
    frame_count = int(args.duration * args.fps)
    # A rotated movie stores its frames turned the other way, so the displayed picture stays upright.
    stored = size if args.rotation in (0, 180) else (size[1], size[0])
    command = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{stored[0]}x{stored[1]}", "-r", str(args.fps), "-i", "-"]
    if args.rotation:
        encoded = args.out.with_suffix(".unrotated.mp4")
    else:
        encoded = args.out
    command += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(encoded)]
    encoder = subprocess.Popen(command, stdin=subprocess.PIPE)

    truth = []
    for index in range(frame_count):
        t = index / args.fps
        frame = draw_frame(args, t, size, label_font)
        if args.rotation:
            frame = frame.rotate(-args.rotation, expand=True)
        encoder.stdin.write(np.asarray(frame, dtype=np.uint8).tobytes())
        x, y, _ = plate_center(args, t)
        truth.append({"time": t, "x": x, "y": y})
    encoder.stdin.close()
    if encoder.wait() != 0:
        raise SystemExit("ffmpeg failed")

    if args.rotation:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-display_rotation", str(args.rotation), "-i", str(encoded), "-c", "copy", str(args.out)],
            check=True,
        )
        encoded.unlink()
    args.out.with_suffix(".truth.json").write_text(json.dumps({"size": size, "fps": args.fps, "frames": truth}))
    print(args.out)


if __name__ == "__main__":
    main()
