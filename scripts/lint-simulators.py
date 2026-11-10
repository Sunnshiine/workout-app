#!/usr/bin/env python3
"""Fail on a simulator an agent could reach outside a Simlock lease (ADR-0024).

Scans every file under scripts/ and .agents/skills/. A simulator comes from `simlock lease`, through
claim_sim or hold_lease in scripts/sim-lock.sh, and is driven by its UDID. Exits 1 and prints one
`error:` line per finding, or 2 when the root has neither directory."""
from __future__ import annotations

import re
import sys
from pathlib import Path

RULES = {
    "lifecycle": (re.compile(r"(?<!simlock )\bsimctl\s+(create|boot|erase|delete|clone|shutdown)\b"),
     "makes, boots, or destroys a simulator outside Simlock; lease one, or run it as simlock simctl"),
    "named": (re.compile(r"(-destination\s*['\"]?|Simulator,)[^'\"\n]*\bname="),
     "names a simulator by model; pass the UDID of a leased one"),
    "tests": (re.compile(r"\bxcodebuild\s+(test|test-without-building)\b"),
     "runs tests on a simulator outside scripts/test-sim.sh, which leases one"),
}
SCANNED = ("scripts", ".agents/skills")
ALL = set(RULES)
# Each exception, the rules it is exempt from, and why. A path ending in / covers its whole tree.
EXCEPTIONS = {
    "scripts/ci/": (ALL, "runs only on a single-tenant GitHub runner, which has no Simlock and no other agent"),
    "scripts/tests/": (ALL, "fakes and fixtures that feed these strings to the scripts under test"),
    ".agents/skills/verify/tests/": (ALL, "fakes and fixtures that feed these strings to verify.sh"),
    "scripts/lint-simulators.py": (ALL, "this lint's own patterns"),
    "scripts/test-sim.sh": ({"tests"}, "runs xcodebuild test-without-building on the simulator claim_sim leased"),
    "scripts/crap.sh": ({"tests"}, "runs xcodebuild test on the platform=macOS destination, which is no simulator"),
    "scripts/flake-guard.sh": ({"tests"}, "runs xcodebuild test-without-building on the platform=macOS destination"),
    "scripts/ci-keyboard-lane.sh": ({"tests"}, "CI's keyboard lane, on the UDID the GitHub runner's job made; "
                                               "locally its usage points at test-sim.sh"),
}


def exempt(relative: str) -> set[str]:
    return set().union(*(rules for path, (rules, _) in EXCEPTIONS.items()
                         if relative == path or (path.endswith("/") and relative.startswith(path))))


def findings(root: Path):
    for entry in SCANNED:
        for file in sorted((root / entry).rglob("*")):
            relative = file.relative_to(root).as_posix()
            skipped = exempt(relative)
            if not file.is_file() or skipped == ALL:
                continue
            try:
                text = file.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for number, line in enumerate(text.splitlines(), start=1):
                for name, (pattern, reason) in RULES.items():
                    if name not in skipped and pattern.search(line):
                        yield f"{relative}:{number}: {reason}: {line.strip()}"


def main(root: Path) -> int:
    if not any((root / entry).is_dir() for entry in SCANNED):
        print(f"error: {root} has neither scripts/ nor .agents/skills/", file=sys.stderr)
        return 2
    found = list(findings(root))
    for line in found:
        print(f"error: {line}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")))
