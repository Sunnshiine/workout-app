#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""The Active Set Card stillness lane, with its positive control.

  SIM=<udid> [VERIFY_RUN=<lane>] uv run .agents/skills/verify/motion/cardstill.py --control COMMIT

Films eight takes through `verify.sh record` twice in one session: first on COMMIT's cached build as run
<lane>-control (stop, launch --at COMMIT --animated session), then on this worktree's build as run
<lane>-head (stop, install, launch --animated session). cardframe measures each take.

A take is INVALID when record did not exit 0 or 3 with a stamp, the stamp is INVALID, its animations are
not on, or it started late; else FAIL when the card was never seen, was lost, or an edge ranged over more
than 0.5 pt; else PASS. The lane FAILs when any head take FAILs, else is INVALID when any take on either
side is, else is INVALID when no control take FAILed (the host or the metric cannot see motion now), else
PASSes.

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

import cardframe

VERIFY = Path(__file__).resolve().parent.parent / "verify.sh"
REST_END_AFTER_S = 22.0


class Setup(Enum):
    NONE = "none"
    LAUNCH = "launch"
    LAUNCH_AND_PAIR = "launch-and-pair"
    AFTER_REST = "after-rest"


@dataclass(frozen=True)
class SetNode:
    """A drive argument that names the branch node `Set N, ...` as the live tree labels it."""

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
    """What one measured take says, as literal values."""

    verdict: str
    invalid: str
    animations: str
    first_seen: Optional[float]
    lost: int
    worst_edge_range: float
    frames: int
    load: str

    @staticmethod
    def of(m: cardframe.Measure) -> "Reading":
        return Reading(
            verdict=m.take.verdict,
            invalid=m.take.invalid,
            animations=m.take.animations,
            first_seen=m.first_seen,
            lost=m.lost,
            worst_edge_range=m.worst_edge_range,
            frames=m.frames,
            load=f"{m.take.load_before}/{m.take.load_after}",
        )


def judge_take(record_exit: int, reading: Optional[Reading], late_s: float = 0.0) -> Tuple[Verdict, str]:
    if record_exit not in (0, 3):
        return Verdict.INVALID, f"record exited {record_exit}"
    if reading is None:
        return Verdict.INVALID, "record left no stamp"
    if reading.verdict != "VALID":
        return Verdict.INVALID, f"take INVALID: {reading.invalid}"
    if reading.animations != "on":
        return Verdict.INVALID, f"animations {reading.animations}"
    if late_s > 0:
        return Verdict.INVALID, f"started {late_s:.1f} s late"
    if reading.first_seen is None:
        return Verdict.FAIL, "no card in any frame"
    if reading.lost > 0:
        return Verdict.FAIL, f"lost the card in {reading.lost} frames"
    if reading.worst_edge_range > cardframe.STILL_PT:
        return Verdict.FAIL, f"an edge moved {reading.worst_edge_range:.1f} pt"
    return Verdict.PASS, ""


@dataclass(frozen=True)
class TakeResult:
    name: str
    verdict: Verdict
    reason: str
    reading: Optional[Reading] = None


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

COLUMNS = ("verdict", "worst_edge", "lost", "frames", "load", "reason")


def cells(r: Optional[TakeResult]) -> List[str]:
    if r is None:
        return [""] * len(COLUMNS)
    g = r.reading
    measured = g is not None and g.first_seen is not None
    return [
        r.verdict.value,
        f"{g.worst_edge_range:.1f}" if measured else "",
        str(g.lost) if measured else "",
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
    """The label of the first tree line whose label starts `Set n,`."""
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
    """verify.sh calls for one run of the lane; SIM comes from the environment."""

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

    def launch(self) -> None:
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

    def record(self, spec: TakeSpec, drive: Sequence[str], late_s: float) -> TakeResult:
        env = {"VERIFY_LOAD_WAIT": "0"} if spec.setup is Setup.AFTER_REST else None
        verb = ["--", *drive] if drive else []
        code, out = self.verify("record", spec.name, "--tail", str(spec.tail), *verb, env=env)
        take = recorded_take(out)
        reading = None
        if code in (0, 3) and take is not None:
            try:
                reading = Reading.of(cardframe.measure(take.with_suffix(".mp4")))
            except (cardframe.Usage, cardframe.DecodeFailure) as error:
                return TakeResult(spec.name, Verdict.INVALID, str(error))
        return TakeResult(spec.name, *judge_take(code, reading, late_s), reading)

    def film(self) -> List[TakeResult]:
        results: List[TakeResult] = []
        superset_logged = None
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
            late_s = 0.0
            try:
                if spec.setup in RELAUNCHES:
                    self.launch()
                if spec.setup is Setup.LAUNCH_AND_PAIR:
                    self.pair()
                if spec.setup is Setup.AFTER_REST:
                    if superset_logged is None:
                        raise SetupFailed("the Superset log take never ran")
                    wait = superset_logged + REST_END_AFTER_S - time.time()
                    late_s = max(0.0, -wait)
                    time.sleep(max(0.0, wait))
                drive = self.drive(spec)
            except SetupFailed as error:
                broken = str(error)
                results.append(TakeResult(spec.name, Verdict.INVALID, broken))
                continue
            results.append(self.record(spec, drive, late_s))
            if spec.name == "superset-log-switch":
                superset_logged = time.time()
            print(f"{self.run} {spec.name} {results[-1].verdict.value} {results[-1].reason}", file=sys.stderr)
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
    control = control_side.film()
    head_side = Side(f"{lane}-head", None)
    head = head_side.film()

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
