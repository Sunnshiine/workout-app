#!/usr/bin/env python3
"""Films one verify.sh drive with simctl recordVideo, and owns the take stamp (NAME.take).

  take.py record --sim UDID --run RUN --verify VERIFY_SH --out PENDING/NAME.mp4 --tail S --limit L
                 --load-before B [-- VERB [ARG...]]
      records from the moment the recorder says it is capturing, runs VERIFY_SH VERB... (its output
      goes to stderr), waits S seconds, stops the recorder with SIGINT only, and prints the stamp's
      take lines on stdout. Exit 0 VALID, 3 INVALID, 1 the drive failed, 70 the recorder or ffprobe
      failed; on 1 and 70 no video is kept. VERIFY_RECORD_START (default 10) is how many seconds
      the recorder gets to start capturing.
  take.py summary NAME.take
      one line on stdout, as `take appear VALID 4.71 s, drive +0.32..+2.69 s, 37 frames, last +3.40 s,
      load 12.3 then 14.0 (limit 50), animations on`; each INVALID reason on stderr

Every time in a stamp but `started` is seconds after `started`, the moment the recorder said it was
capturing. Frame times are the video's own pts: recordVideo writes a frame only when the screen
changes, so frame count and container duration say nothing about coverage.
"""
import argparse
import dataclasses
import json
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

STOP_GRACE = 15.0
POLL = 0.05


@dataclasses.dataclass(frozen=True)
class Take:
    name: str
    video: str
    drive: str
    tail: float
    load_limit: float
    load_before: float
    load_after: float
    started: float
    drive_start: float
    drive_end: float
    stopped: float
    recorder_exit: int
    recorder_early: bool
    frames: int
    first_frame: float
    last_frame: float
    video_px: Tuple[int, int]
    screen_pt: Optional[Tuple[int, int]] = None
    animations: str = "unknown"
    app: str = ""


def seconds(value: float) -> str:
    return "%.3f" % value


def pixels(text: str) -> Tuple[int, int]:
    width, height = text.split("x")
    return int(width), int(height)


FIELDS = {
    "name": (str, str),
    "video": (str, str),
    "drive": (str, str),
    "tail": (float, repr),
    "load_limit": (float, "{:g}".format),
    "load_before": (float, "{:.2f}".format),
    "load_after": (float, "{:.2f}".format),
    "started": (float, seconds),
    "drive_start": (float, seconds),
    "drive_end": (float, seconds),
    "stopped": (float, seconds),
    "recorder_exit": (int, str),
    "recorder_early": (lambda text: text == "1", lambda early: "1" if early else "0"),
    "frames": (int, str),
    "first_frame": (float, seconds),
    "last_frame": (float, seconds),
    "video_px": (pixels, lambda px: "%dx%d" % px),
}
# verify.sh appends these after take.py prints the rest, because only it knows the screen and the launch.
APPENDED = {"screen_pt": pixels, "animations": str, "app": str}


def judge(take: Take) -> List[str]:
    """Why the take is INVALID, one reason per failed rule; empty when it is VALID."""
    reasons = []
    for moment, load in [("the start", take.load_before), ("the end", take.load_after)]:
        if load >= take.load_limit:
            reasons.append("load %.1f at %s, at or over %g" % (load, moment, take.load_limit))
            break
    if take.recorder_early:
        reasons.append("the recorder stopped before the take ended")
    if take.recorder_exit != 0:
        reasons.append("recorder exit %d after SIGINT; the video may be cut short" % take.recorder_exit)
    # The first frame is the screen as the recorder found it, so only a later one can show the drive.
    if take.drive and (take.frames < 2 or take.last_frame < take.drive_start):
        reasons.append("the screen never changed after the drive began at +%.2f s, so the take shows nothing "
                       "the drive did" % take.drive_start)
    if not take.drive and take.frames < 2:
        reasons.append("one frame: the screen never changed while recording")
    return reasons


def take_lines(take: Take) -> List[str]:
    reasons = judge(take)
    lines = ["format=take/1"]
    lines += ["%s=%s" % (key, render(getattr(take, key))) for key, (_, render) in FIELDS.items()]
    lines += ["verdict=%s" % ("INVALID" if reasons else "VALID"), "invalid=%s" % "; ".join(reasons)]
    return lines


def parse(text: str) -> Take:
    found = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
    if found.get("format") != "take/1":
        raise ValueError("format=%s, not take/1" % found["format"] if "format" in found else "no format=take/1")
    missing = [key + "=" for key in FIELDS if key not in found]
    if missing:
        raise ValueError("no %s" % " ".join(missing))
    readers = dict({key: read for key, (read, _) in FIELDS.items()}, **APPENDED)
    values = {}
    for key, read in readers.items():
        if key in found:
            try:
                values[key] = read(found[key])
            except ValueError:
                raise ValueError("%s=%s does not parse" % (key, found[key])) from None
    return Take(**values)


def summary(take: Take) -> str:
    drive = "drive +%.2f..+%.2f s" % (take.drive_start, take.drive_end) if take.drive else "no drive"
    return "take %s %s %.2f s, %s, %d frame%s, last +%.2f s, load %.1f then %.1f (limit %g), animations %s" % (
        take.name, "INVALID" if judge(take) else "VALID", take.stopped, drive, take.frames,
        "" if take.frames == 1 else "s", take.last_frame, take.load_before, take.load_after, take.load_limit,
        take.animations)


class NoTake(Exception):
    """The recorder or ffprobe failed, so there is no video to judge."""


class DriveFailed(Exception):
    pass


class Interrupted(Exception):
    pass


def interrupted(signum, _frame):
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    raise Interrupted(signum)


class Recorder:
    def __init__(self, sim: str, out: Path):
        self.log = out.with_name(out.name + ".log")
        with open(str(self.log), "wb") as log:
            # Its own session, so a Ctrl-C at the terminal reaches it only as the SIGINT this script forwards.
            self.proc = subprocess.Popen(
                ["xcrun", "simctl", "io", sim, "recordVideo", "--codec", "h264", "--force", str(out)],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)

    def output(self) -> str:
        return self.log.read_text(errors="replace").strip()

    def failed(self, why: str) -> NoTake:
        said = self.output()
        return NoTake("simctl recordVideo %s, so nothing was driven%s" % (why, ":\n" + said if said else ""))

    def await_capture(self, timeout: float) -> float:
        deadline = time.time() + timeout
        while "Recording started" not in self.output():
            if self.proc.poll() is not None:
                raise self.failed("exited %d before it started capturing" % self.proc.returncode)
            if time.time() > deadline:
                self.stop()
                raise self.failed("did not start capturing within %g s" % timeout)
            time.sleep(POLL)
        return time.time()

    def stop(self) -> int:
        """SIGINT and wait. Never SIGTERM or SIGKILL: a recorder killed mid-write leaves an mp4 with no index."""
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGINT)
        deadline = time.time() + STOP_GRACE
        while self.proc.poll() is None:
            if time.time() > deadline:
                raise NoTake("simctl recordVideo (pid %d) is still running %g s after SIGINT; stop it with: kill -INT %d"
                             % (self.proc.pid, STOP_GRACE, self.proc.pid))
            time.sleep(POLL)
        return self.proc.returncode


def load_now() -> float:
    """The 1-minute load average, field 2 of `sysctl -n vm.loadavg` ("{ 12.31 9.80 8.71 }")."""
    out = subprocess.run(["sysctl", "-n", "vm.loadavg"], stdout=subprocess.PIPE, universal_newlines=True,
                         check=True).stdout
    return float(out.split()[1])


def probe(video: Path) -> Tuple[List[float], Tuple[int, int]]:
    done = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time:stream=width,height",
         "-of", "json", str(video)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    try:
        if done.returncode != 0:
            raise ValueError(done.stderr.strip())
        found = json.loads(done.stdout)
        pts = sorted(float(frame["pts_time"]) for frame in found.get("frames", []))
        stream = found["streams"][0]
        size = (int(stream["width"]), int(stream["height"]))
    except (ValueError, KeyError, IndexError) as error:
        raise NoTake("ffprobe could not read %s: %s" % (video, error))
    if not pts:
        raise NoTake("ffprobe found no frame in %s" % video)
    return pts, size


def film(sim: str, run: str, verify: str, out: Path, tail: float, limit: float, load_before: float,
         drive: Sequence[str], start_timeout: float) -> Take:
    recorder = Recorder(sim, out)
    try:
        started = recorder.await_capture(start_timeout)
        drive_start = time.time() - started
        if drive:
            ran = subprocess.run([verify] + list(drive), stdin=subprocess.DEVNULL, stdout=sys.stderr.fileno(),
                                 stderr=sys.stderr.fileno(), env=dict(os.environ, SIM=sim, VERIFY_RUN=run))
            if ran.returncode != 0:
                raise DriveFailed("the drive `%s` exited %d, so the take is not kept" % (shlex.join(drive), ran.returncode))
        drive_end = time.time() - started
        time.sleep(tail)
        early = recorder.proc.poll() is not None
        stopped = time.time() - started
        recorder_exit = recorder.stop()
    finally:
        recorder.stop()
    try:
        load_after = load_now()
    except (OSError, subprocess.CalledProcessError, ValueError, IndexError) as error:
        raise NoTake("could not read the load after the take: %s" % error)
    pts, size = probe(out)
    return Take(
        name=out.stem, video=out.name, drive=shlex.join(drive), tail=tail, load_limit=limit,
        load_before=round(load_before, 2), load_after=round(load_after, 2), started=round(started, 3),
        drive_start=round(drive_start, 3), drive_end=round(drive_end, 3), stopped=round(stopped, 3),
        recorder_exit=recorder_exit, recorder_early=early, frames=len(pts), first_frame=round(pts[0], 3),
        last_frame=round(pts[-1], 3), video_px=size)


def record(argv: List[str]) -> int:
    flags, drive = (argv[:argv.index("--")], argv[argv.index("--") + 1:]) if "--" in argv else (argv, [])
    parser = argparse.ArgumentParser(prog="take.py record")
    for flag in ["--sim", "--run", "--verify", "--out"]:
        parser.add_argument(flag, required=True)
    for flag in ["--tail", "--limit", "--load-before"]:
        parser.add_argument(flag, required=True, type=float)
    args = parser.parse_args(flags)
    out = Path(args.out)
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    try:
        take = film(args.sim, args.run, args.verify, out, args.tail, args.limit, args.load_before, drive,
                    float(os.environ.get("VERIFY_RECORD_START", "10")))
    except Interrupted as signum:
        out.unlink(missing_ok=True)
        return 128 + signum.args[0]
    except (DriveFailed, NoTake) as failure:
        out.unlink(missing_ok=True)
        print(failure, file=sys.stderr)
        return 1 if isinstance(failure, DriveFailed) else 70
    finally:
        out.with_name(out.name + ".log").unlink(missing_ok=True)
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
    print("\n".join(take_lines(take)))
    return 3 if judge(take) else 0


def report(path: str) -> int:
    take = parse(Path(path).read_text())
    print(summary(take))
    for reason in judge(take):
        print(reason, file=sys.stderr)
    if take.animations == "off":
        print("animations are off in this app (it was launched without --animated), so the take cannot show motion",
              file=sys.stderr)
    return 0


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "record":
        sys.exit(record(sys.argv[2:]))
    if command == "summary" and len(sys.argv) == 3:
        sys.exit(report(sys.argv[2]))
    print(__doc__, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
