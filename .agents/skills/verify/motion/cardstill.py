#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""The Active Set Card stillness lane, with its positive control.

  SIM=<udid> [VERIFY_RUN=<lane>] uv run .agents/skills/verify/motion/cardstill.py --control COMMIT

Films eight takes through `verify.sh record` twice in one session: first on COMMIT's cached build as run
<lane>-control (stop, launch --at COMMIT --animated session), then on this worktree's build as run
<lane>-head (stop, install, launch --animated session). cardframe measures every take once both sides are
filmed, so measuring never loads the host before a take. The rest-end take starts 26 s after the Superset
log tap, timed from that take's stamp, and is late when its own stamp started more than 2 s after that.

A take is INVALID when record did not exit 0 or 3 with a stamp. Else it FAILs when the card was lost or an
edge ranged over more than 0.5 pt, even on a take INVALID only for load at its end or for a window shorter
than its tail, or with animations off, because those can hide motion but never invent it. Else it is
INVALID when the take is INVALID, its animations are not on, it started late, or the card is in no frame,
because then the metric saw nothing and the take proves nothing; else PASS. So only a lost card or a moved
edge FAILs a take, on either side, and only those satisfy the control. The lane FAILs when any head take
FAILs, else is INVALID when any take on either side is, else is INVALID when no control take FAILed (the
host or the metric cannot see motion now), else PASSes. The look inside the box is printed beside the box
and never judged, because the static-card rule lets content change inside a box that never moves.

Prints one row per take, control and head side by side, then `cardstill PASS|FAIL|INVALID: <reason>`, and
writes the table as cardstill.tsv in the head run's evidence directory. The app must be built
(`verify.sh build`). Exit 0 PASS, 1 FAIL, 3 INVALID, 2 usage.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple, Union

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import cardframe  # noqa: E402
import take  # noqa: E402

VERIFY = Path(__file__).resolve().parent.parent / "verify.sh"
REST_END_AFTER_S = 26.0
LATE_S = 2.0


class Setup(Enum):
    NONE = "none"
    LAUNCH = "launch"
    LAUNCH_AND_PAIR = "launch-and-pair"
    AFTER_REST = "after-rest"


@dataclass(frozen=True)
class SetNode:
    n: int


@dataclass(frozen=True)
class TakeSpec:
    name: str
    drive: Tuple[Union[str, SetNode], ...]
    tail: float
    setup: Setup = Setup.NONE


TAKES: Tuple[TakeSpec, ...] = (
    TakeSpec("single-log-rest-start", ("tap", "--id", "log-active-set-button"), 3, Setup.LAUNCH),
    TakeSpec("node-tap", ("tap", "--label", SetNode(3)), 2),
    TakeSpec("review-open", ("tap", "--label", SetNode(1)), 2),
    TakeSpec("review-collapse", ("tap", "--label", "Collapse logged set"), 2),
    TakeSpec("superset-log-switch", ("tap", "--id", "log-active-set-button"), 3, Setup.LAUNCH_AND_PAIR),
    TakeSpec("partner-tap", ("tap", "--id", "superset-partner-name"), 2),
    TakeSpec("partner-tap-back", ("tap", "--id", "superset-partner-name"), 2),
    TakeSpec("superset-rest-end", (), 14, Setup.AFTER_REST),
)

PAIR_TAPS: Tuple[Tuple[str, float], ...] = (
    ("stage-queue-button", 0),
    ("stage-queue-pair-exercise-0", 0),
    ("stage-queue-row-exercise-1", 1),
    ("stage-queue-row-superset-0", 2),
)


class Verdict(Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    INVALID = "INVALID"


@dataclass(frozen=True)
class Reading:
    rules: Tuple[str, ...]
    invalid: str
    animations: str
    first_seen: Optional[float]
    lost: int
    worst_edge_range: float
    look: str
    frames: int
    load: str

    @staticmethod
    def of(m: cardframe.Measure) -> "Reading":
        box = m.card.box if m.card else None
        return Reading(
            rules=tuple(r.rule for r in m.invalid),
            invalid="; ".join(r.text for r in m.invalid),
            animations=m.take.animations,
            first_seen=box.first_seen if box else None,
            lost=box.lost if box else 0,
            worst_edge_range=box.worst_edge_range if box else 0.0,
            look=look_text(m.card.look) if m.card else "",
            frames=m.frames,
            load=f"{m.take.load_before:.2f}/{m.take.load_after:.2f}",
        )


def look_text(look: cardframe.Look) -> str:
    return f"changed {look.ms} ms" if look.kind is cardframe.LookKind.CHANGED else look.kind.value


def judge_take(record_exit: int, reading: Optional[Reading], late_s: float = 0.0) -> Tuple[Verdict, str]:
    if record_exit not in (0, 3):
        return Verdict.INVALID, f"record exited {record_exit}"
    if reading is None:
        return Verdict.INVALID, "record left no stamp"
    seen_soundly = reading.first_seen is not None and set(reading.rules) <= cardframe.HIDES_MOTION
    if seen_soundly and reading.lost > 0:
        return Verdict.FAIL, f"lost the card in {reading.lost} frames"
    if seen_soundly and reading.worst_edge_range > cardframe.STILL_PT:
        return Verdict.FAIL, f"an edge moved {reading.worst_edge_range:.1f} pt"
    if reading.rules:
        return Verdict.INVALID, f"take INVALID: {reading.invalid}"
    if reading.animations != "on":
        return Verdict.INVALID, f"animations {reading.animations}"
    if late_s > 0:
        return Verdict.INVALID, f"started {late_s:.1f} s late"
    if reading.first_seen is None:
        return Verdict.INVALID, "no card in any frame"
    return Verdict.PASS, ""


@dataclass(frozen=True)
class TakeResult:
    name: str
    verdict: Verdict
    reason: str
    reading: Optional[Reading] = None


@dataclass(frozen=True)
class Filmed:
    name: str
    record_exit: int
    path: Optional[Path]
    late_s: float = 0.0


def rest_end_at(switch: take.Take) -> float:
    return switch.started + switch.drive_end + REST_END_AFTER_S


def late_by(target: float, rest_end: take.Take) -> float:
    over = rest_end.started - target
    return over if over > LATE_S else 0.0


def parsed_stamp(record_exit: int, path: Optional[Path]) -> Optional[take.Take]:
    if record_exit not in (0, 3) or path is None:
        return None
    try:
        return take.parse(path.read_text())
    except (OSError, ValueError):
        return None


def measured(filmed: Union[Filmed, TakeResult]) -> TakeResult:
    if isinstance(filmed, TakeResult):
        return filmed
    reading = None
    if filmed.record_exit in (0, 3) and filmed.path is not None:
        try:
            reading = Reading.of(cardframe.measure(filmed.path.with_suffix(".mp4")))
        except (cardframe.Usage, cardframe.DecodeFailure) as error:
            return TakeResult(filmed.name, Verdict.INVALID, str(error))
    return TakeResult(filmed.name, *judge_take(filmed.record_exit, reading, filmed.late_s), reading)


def lane_verdict(control_sha: str, control: Sequence[TakeResult], head: Sequence[TakeResult]) -> Tuple[Verdict, str]:
    failed = [r for r in head if r.verdict is Verdict.FAIL]
    if failed:
        return Verdict.FAIL, "; ".join(f"head {r.name}: {r.reason}" for r in failed)
    invalid = [(side, r) for side, rs in (("control", control), ("head", head)) for r in rs
               if r.verdict is Verdict.INVALID]
    if invalid:
        return Verdict.INVALID, "; ".join(f"{side} {r.name}: {r.reason}" for side, r in invalid)
    if not any(r.verdict is Verdict.FAIL for r in control):
        return Verdict.INVALID, (f"the control {control_sha} held the card still on every take, so this host "
                                 "or this metric cannot see motion now")
    moved = sum(1 for r in control if r.verdict is Verdict.FAIL)
    return Verdict.PASS, f"the head held the card still on every take; the control {control_sha} moved it on {moved}"


EXIT = {Verdict.PASS: 0, Verdict.FAIL: 1, Verdict.INVALID: 3}

COLUMNS = ("verdict", "worst_edge", "lost", "look", "frames", "load", "reason")


def cells(r: Optional[TakeResult]) -> List[str]:
    if r is None:
        return [""] * len(COLUMNS)
    g = r.reading
    measured = g is not None and g.first_seen is not None
    return [
        r.verdict.value,
        f"{g.worst_edge_range:.1f}" if measured else "",
        str(g.lost) if measured else "",
        g.look if g else "",
        str(g.frames) if g else "",
        g.load if g else "",
        r.reason,
    ]


def table(control: Sequence[TakeResult], head: Sequence[TakeResult]) -> List[List[str]]:
    by_side = [{r.name: r for r in side} for side in (control, head)]
    header = ["take"] + [f"{side}_{c}" for side in ("control", "head") for c in COLUMNS]
    return [header] + [[spec.name] + cells(by_side[0].get(spec.name)) + cells(by_side[1].get(spec.name))
                       for spec in TAKES]


def node_label(tree: str, n: int) -> Optional[str]:
    for line in tree.splitlines():
        fields = line.split("\t")
        if len(fields) > 2 and fields[2].startswith(f"Set {n},"):
            return fields[2]
    return None


def recorded_take(stdout: str) -> Optional[Path]:
    return next((Path(line) for line in stdout.splitlines() if line.endswith(".take")), None)


def evidence_dir(stdout: str) -> Optional[Path]:
    return next((Path(line[len("evidence "):]) for line in stdout.splitlines() if line.startswith("evidence ")),
                None)


RELAUNCHES = (Setup.LAUNCH, Setup.LAUNCH_AND_PAIR)


class SetupFailed(Exception):
    pass


class Side:
    def __init__(self, run: str, at: Optional[str]) -> None:
        self.run = run
        self.at = at
        self.evidence: Optional[Path] = None

    def verify(self, *argv: str, env: Optional[Dict[str, str]] = None) -> Tuple[int, str]:
        done = subprocess.run([str(VERIFY), *argv], env={**os.environ, "VERIFY_RUN": self.run, **(env or {})},
                              stdout=subprocess.PIPE, universal_newlines=True)
        sys.stderr.write(done.stdout)
        return done.returncode, done.stdout

    def must(self, *argv: str) -> str:
        code, out = self.verify(*argv)
        if code != 0:
            raise SetupFailed(f"verify.sh {' '.join(argv)} exited {code}")
        return out

    def relaunch(self) -> None:
        self.verify("stop")
        at = ("--at", self.at) if self.at else ()
        self.evidence = evidence_dir(self.must("launch", *at, "--animated", "session")) or self.evidence

    def pair(self) -> None:
        for ident, settle in PAIR_TAPS:
            self.must("tap", "--id", ident)
            time.sleep(settle)

    def drive(self, spec: TakeSpec) -> List[str]:
        if not any(isinstance(arg, SetNode) for arg in spec.drive):
            return [str(arg) for arg in spec.drive]
        tree = self.must("tree")
        argv = []
        for arg in spec.drive:
            if isinstance(arg, SetNode):
                label = node_label(tree, arg.n)
                if label is None:
                    raise SetupFailed(f"no Set {arg.n} node on screen")
                arg = label
            argv.append(arg)
        return argv

    def record(self, spec: TakeSpec, drive: Sequence[str]) -> Tuple[int, Optional[Path]]:
        env = {"VERIFY_LOAD_WAIT": "0"} if spec.setup is Setup.AFTER_REST else None
        verb = ["--", *drive] if drive else []
        code, out = self.verify("record", spec.name, "--tail", str(spec.tail), *verb, env=env)
        return code, recorded_take(out)

    def film(self) -> List[Union[Filmed, TakeResult]]:
        results: List[Union[Filmed, TakeResult]] = []
        rest_end_target = None
        prologue = None
        try:
            self.must("stop")
            if self.at is None:
                self.must("install")
        except SetupFailed as error:
            prologue = str(error)
        broken = prologue
        for spec in TAKES:
            if spec.setup in RELAUNCHES:
                broken = prologue
            if broken:
                results.append(TakeResult(spec.name, Verdict.INVALID, broken))
                continue
            try:
                if spec.setup in RELAUNCHES:
                    self.relaunch()
                if spec.setup is Setup.LAUNCH_AND_PAIR:
                    self.pair()
                if spec.setup is Setup.AFTER_REST:
                    if rest_end_target is None:
                        raise SetupFailed("the Superset log take left no stamp to time the rest end from")
                    time.sleep(max(0.0, rest_end_target - time.time()))
                drive = self.drive(spec)
            except SetupFailed as error:
                broken = str(error)
                results.append(TakeResult(spec.name, Verdict.INVALID, broken))
                continue
            code, path = self.record(spec, drive)
            stamp = parsed_stamp(code, path)
            late_s = 0.0
            if spec.name == "superset-log-switch" and stamp is not None:
                rest_end_target = rest_end_at(stamp)
            if spec.setup is Setup.AFTER_REST and stamp is not None:
                late_s = late_by(rest_end_target, stamp)
            results.append(Filmed(spec.name, code, path, late_s))
        self.verify("stop")
        return results


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="cardstill.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--control", required=True, help="a commit whose build moves the card")
    args = parser.parse_args(argv)
    if not os.environ.get("SIM"):
        print("SIM is not set; name your lane simulator: SIM=<udid> cardstill.py --control COMMIT", file=sys.stderr)
        return 2
    lane = os.environ.get("VERIFY_RUN") or time.strftime("cardstill-%Y%m%d-%H%M%S")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*", lane):
        print(f"VERIFY_RUN is letters, digits and dashes, starting with a letter or digit: {lane}", file=sys.stderr)
        return 2

    control_side = Side(f"{lane}-control", args.control)
    head_side = Side(f"{lane}-head", None)
    control_filmed = control_side.film()
    head_filmed = head_side.film()
    control = [measured(f) for f in control_filmed]
    head = [measured(f) for f in head_filmed]

    rows = table(control, head)
    width = [max(len(row[i]) for row in rows) for i in range(len(rows[0]) - 1)]
    for row in rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, width)) + "  " + row[-1])
    if head_side.evidence is not None:
        (head_side.evidence / "cardstill.tsv").write_text("".join("\t".join(row) + "\n" for row in rows))
        print(head_side.evidence / "cardstill.tsv")
    verdict, reason = lane_verdict(args.control, control, head)
    print(f"cardstill {verdict.value}: {reason}")
    return EXIT[verdict]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
