#!/usr/bin/env bash
# Print the table that pairs each written rule with the check that enforces it.
set -euo pipefail

usage() {
    cat <<'EOF'
usage: scripts/rule-table.sh [--check | --write] [ROOT]

  scripts/rule-table.sh            print the rule table
  scripts/rule-table.sh --check    also fail when AGENTS.md's table differs from it
  scripts/rule-table.sh --write    rewrite AGENTS.md's table from it

Each top-level bullet of CODING_STANDARDS.md is a rule. It starts with a bold lead and ends with
"Enforced by: <names>.", where each name is a backticked custom SwiftLint rule, file, or test type,
or the bare word judgment. The table lists every bullet with its enforcers. Then it lists each
custom SwiftLint rule, each check scripts/lint.sh runs, and each workflow step that runs a scripts/
file, when no bullet names it, under its own SwiftLint name, lint.sh label, or step name.

Exits 0 when clean, 1 when a bullet names no enforcer, names one the tree lacks, or AGENTS.md
drifts (--check), and 64 on a usage error.
EOF
}

mode=print
root=""
for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        --check) mode=check ;;
        --write) mode=write ;;
        -*) usage >&2; exit 64 ;;
        *)
            [ -z "$root" ] || { usage >&2; exit 64; }
            root=$arg
            ;;
    esac
done
root=${root:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
[ -f "$root/CODING_STANDARDS.md" ] || { echo "error: $root has no CODING_STANDARDS.md." >&2; exit 64; }

exec python3 - "$mode" "$root" <<'PY'
from __future__ import annotations

import difflib
import glob
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional

mode, root = sys.argv[1], sys.argv[2]
STANDARDS = "CODING_STANDARDS.md"
AGENTS = "AGENTS.md"
START = "<!-- rule-table:start -->"
END = "<!-- rule-table:end -->"
# Steps that boot a runner or ship a build judge no change. lint.sh is listed by the checks it runs.
NOT_CHECKS = ("scripts/lint.sh", "scripts/ensure-simulator.sh", "scripts/sim-slim.sh")
NOT_CHECK_DIRS = ("scripts/tests/", "scripts/ci/")


@dataclass
class Enforcer:
    name: str
    describes: str
    runs_in: List[str] = field(default_factory=list)


@dataclass
class Rule:
    line: int
    lead: str
    names: List[str]
    judgment: bool


def read(path: str) -> str:
    with open(os.path.join(root, path), encoding="utf-8") as f:
        return f.read()


def swiftlint_rules() -> Dict[str, Enforcer]:
    found: Dict[str, Enforcer] = {}
    if not os.path.exists(os.path.join(root, ".swiftlint.yml")):
        return found
    inside = False
    current = None
    for line in read(".swiftlint.yml").splitlines():
        if line.startswith("custom_rules:"):
            inside = True
            continue
        if not inside:
            continue
        if re.match(r"[^\s#]", line):
            break
        key = re.match(r"  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
        if key:
            current = key.group(1)
            found[current] = Enforcer(current, current, ["lint.sh"])
            continue
        name = re.match(r'    name:\s*"?(.*?)"?\s*$', line)
        if name and current:
            found[current].describes = name.group(1)
    return found


def lint_checks() -> Dict[str, Enforcer]:
    found: Dict[str, Enforcer] = {}
    label = None
    for line in read("scripts/lint.sh").splitlines():
        echo = re.match(r'\s*echo "==> (.*)"\s*$', line)
        if echo:
            label = echo.group(1)
            continue
        call = re.search(r"scripts/([\w.-]+)", line)
        if label and call and not line.lstrip().startswith("#"):
            script = "scripts/" + call.group(1)
            where = "lint.sh, advisory" if re.search(r"\|\|\s*true\s*$", line) else "lint.sh"
            found[script] = Enforcer(script, re.sub(r"\s*\(advisory\)$", "", label), [where])
            label = None
    return found


def workflow_steps() -> Dict[str, Enforcer]:
    found: Dict[str, Enforcer] = {}
    for path in sorted(glob.glob(os.path.join(root, ".github/workflows/*.yml"))):
        workflow = os.path.basename(path)
        step = None
        with open(path, encoding="utf-8") as f:
            for line in f:
                named = re.match(r"\s*- name:\s*(.*?)\s*$", line)
                if named:
                    step = named.group(1).strip("\"'")
                    continue
                if re.match(r"\s*- ", line):
                    step = None
                if step is None or line.lstrip().startswith("#") or "--print-version" in line:
                    continue
                call = re.search(r"scripts/[\w./-]+", line)
                if call is None or call.group(0) in NOT_CHECKS or call.group(0).startswith(NOT_CHECK_DIRS):
                    continue
                enforcer = found.setdefault(call.group(0), Enforcer(call.group(0), step))
                if workflow not in enforcer.runs_in:
                    enforcer.runs_in.append(workflow)
    return found


def test_type(name: str) -> Optional[str]:
    pattern = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:final\s+)?(?:struct|class|enum)\s+" + re.escape(name) + r"\b", re.M)
    for path in sorted(glob.glob(os.path.join(root, "Tests/**/*.swift"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            if pattern.search(f.read()):
                relative = os.path.relpath(path, root)
                return "simulator" if relative.startswith(("Tests/UI/", "Tests/Visual/")) else "swift test"
    return None


def rules(errors: List[str]) -> List[Rule]:
    bullets: List[List] = []
    open_bullet = False
    for number, line in enumerate(read(STANDARDS).splitlines(), 1):
        if line.startswith("- "):
            bullets.append([number, line[2:]])
            open_bullet = True
        elif open_bullet and line.startswith("  ") and line.strip():
            bullets[-1][1] += " " + line.strip()
        else:
            open_bullet = False
    parsed: List[Rule] = []
    for number, text in bullets:
        where = f"{STANDARDS}:{number}"
        lead = re.match(r"\*\*(.+?)\*\*", text)
        if not lead:
            errors.append(f"{where}: this bullet has no bold lead. Start each rule with **the defect it names**.")
            continue
        title = lead.group(1).rstrip(",.:; ")
        tail = re.search(r"Enforced by: (.+?)\.$", text)
        if not tail:
            errors.append(
                f"{where}: the bullet \"{title}\" names no enforcer. End it with "
                "\"Enforced by: `<SwiftLint rule, file, or test>`.\", or \"Enforced by: judgment.\" "
                "when no check can judge it."
            )
            continue
        names, judgment = [], False
        for token in re.split(r",\s*(?:and\s+)?|\s+and\s+", tail.group(1)):
            token = token.strip()
            if token == "judgment":
                judgment = True
            elif re.fullmatch(r"`[^`]+`", token):
                names.append(token.strip("`"))
            else:
                errors.append(f"{where}: \"{token}\" in \"{title}\" is neither a backticked name nor judgment.")
        parsed.append(Rule(number, title, names, judgment))
    return parsed


def resolve(name: str, known: Dict[str, Enforcer]) -> Optional[Enforcer]:
    if name in known:
        return known[name]
    if "/" in name and os.path.exists(os.path.join(root, name)):
        if name.startswith(("Tests/Unit/", "Tests/Component/")):
            return Enforcer(name, name, ["swift test"])
        if name.startswith(("Tests/UI/", "Tests/Visual/")):
            return Enforcer(name, name, ["simulator"])
        return Enforcer(name, name, ["by hand"])
    if re.fullmatch(r"[A-Z]\w*", name):
        where = test_type(name)
        if where:
            return Enforcer(name, name, [where])
    return None


def cell(enforcer: Enforcer) -> str:
    return f"`{enforcer.name}` ({', '.join(enforcer.runs_in)})"


def table(errors: List[str]) -> str:
    known: Dict[str, Enforcer] = {}
    for source in (swiftlint_rules(), lint_checks(), workflow_steps()):
        for name, enforcer in source.items():
            if name in known:
                known[name].describes = enforcer.describes
                known[name].runs_in += [r for r in enforcer.runs_in if r not in known[name].runs_in]
            else:
                known[name] = enforcer
    rows = ["| Rule | Enforced by |", "|---|---|"]
    claimed = set()
    for rule in rules(errors):
        cells = []
        for name in rule.names:
            enforcer = resolve(name, known)
            if enforcer is None:
                errors.append(
                    f"{STANDARDS}:{rule.line}: \"{rule.lead}\" names `{name}`, which is no custom "
                    "SwiftLint rule, file, or test type in this tree."
                )
                continue
            claimed.add(name)
            cells.append(cell(enforcer))
        if rule.judgment:
            cells.append("judgment")
        rows.append(f"| {rule.lead} | {', '.join(cells)} |")
    for name, enforcer in known.items():
        if name not in claimed:
            rows.append(f"| {enforcer.describes} | {cell(enforcer)} |")
    return "\n".join(rows) + "\n"


def agents_block(text: str) -> Optional[re.Match]:
    return re.search(re.escape(START) + r"\n(.*?)" + re.escape(END), text, re.S)


errors: List[str] = []
printed = table(errors)
if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    sys.exit(1)

if mode == "print":
    sys.stdout.write(printed)
    sys.exit(0)

agents = read(AGENTS)
block = agents_block(agents)
if block is None:
    print(f"error: {AGENTS} has no {START} ... {END} block to hold the table.", file=sys.stderr)
    sys.exit(1)
if mode == "write":
    with open(os.path.join(root, AGENTS), "w", encoding="utf-8") as f:
        f.write(agents[: block.start(1)] + printed + agents[block.end(1) :])
    sys.exit(0)
if block.group(1) != printed:
    sys.stdout.writelines(
        difflib.unified_diff(
            block.group(1).splitlines(True), printed.splitlines(True), f"{AGENTS} (held)", "scripts/rule-table.sh"
        )
    )
    print(f"error: {AGENTS}'s rule table differs from what the tree enforces. Run scripts/rule-table.sh --write.", file=sys.stderr)
    sys.exit(1)
rows = printed.splitlines()[2:]
judged = sum(row.endswith("| judgment |") for row in rows)
print(f"==> Clean: {len(rows)} rules, {len(rows) - judged} with a check, {judged} by judgment alone")
PY
