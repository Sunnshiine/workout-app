#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Print the test IDs that cover the given files, one per line, for scripts/test-sim.sh.

usage: scripts/tests-for.py [--base REV] [FILE | TEST-FUNCTION]...

  scripts/tests-for.py App/Views/OnboardingView.swift
      WorkoutTrackerSnapshotTests/SunbirdMomentsVisualTests
      WorkoutTrackerUITests/WorkoutTrackerInteractionUITests
      WorkoutTrackerUITests/WorkoutTrackerOnboardingSwitchUITests
      WorkoutTrackerUITests/WorkoutTrackerUISmokeTests
  scripts/test-sim.sh $(scripts/tests-for.py App/Views/OnboardingView.swift | grep ^WorkoutTrackerSnapshotTests/)
  scripts/tests-for.py testOnboardingSheetSelectionAutoSyncsAndReplacesStaleCachedBlock
      WorkoutTrackerUITests/WorkoutTrackerOnboardingSwitchUITests/testOnboardingSheetSelectionAutoSyncsAndReplacesStaleCachedBlock
  scripts/tests-for.py          # the .swift files this branch changed since it left origin/main

A file's IDs are <test target>/<suite>, the -only-testing form test-sim.sh takes. A suite covers a
file when it names one of the file's top-level types or a repo type the file extends, or, for a UI
test, an accessibilityIdentifier string the file sets. A test helper with no suite, such as a
Visual test host, passes the match on to the suites in its folder that use it. A file no suite
names, such as a small view inside a larger one, takes the suites of the nearest files that use
it, and says which on stderr. A test file prints its own suites. Line comments do not count. An
App/ file nothing reaches, such as the app entry point, prints nothing; every UI test launches it.
An @Test function outside every type is its own suite, <test target>/<name>(). A bare name
prints the full ID of each test function with that name.

A file under Tests/<Folder>/ belongs to the test target whose buildable folders include <Folder>
in WorkoutTracker.xcodeproj: Visual is WorkoutTrackerSnapshotTests, UI is WorkoutTrackerUITests,
and Unit and Component are WorkoutTrackerTests, whose suites swift test --filter <suite> also runs.

With no argument, reads the .swift files that HEAD and the working tree changed since HEAD left
REV (default origin/main). Exits 0, or 2 on a usage error.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

DECLARATION = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|final|open|nonisolated)\s+)*"
    r"(struct|class|enum|actor|protocol|extension)\s+([A-Z]\w*)",
    re.MULTILINE,
)
IDENTIFIER = re.compile(r'accessibilityIdentifier\("([^"\\]{3,})')
TEST_MARK = re.compile(r"@Test\b|: XCTestCase\b")
COMMENT = re.compile(r"//.*")
GLOBAL_TEST = re.compile(r"@Test\b(?:\((?:[^()]|\([^()]*\))*\))?\s*(?:@\w+\s*)*(?:(?:private|fileprivate|nonisolated)\s+)*func\s+(\w+)")


def brace_depths(code: str) -> list[int]:
    depth, depths = 0, []
    for char in code:
        depths.append(depth)
        depth += {"{": 1, "}": -1}.get(char, 0)
    return depths


def global_tests(code: str) -> list[str]:
    """The @Test functions declared outside every type, which Swift Testing runs as <target>/<name>()."""
    depths = brace_depths(code)
    return [m.group(1) for m in GLOBAL_TEST.finditer(code) if depths[m.start()] == 0]


def declarations(code: str) -> list[tuple[str, str, str]]:
    """Top-level (kind, name, body) triples: those outside every brace, #if blocks included."""
    depths = brace_depths(code)
    triples = []
    for m in DECLARATION.finditer(code):
        if depths[m.start(1)] != 0:
            continue
        opened = code.find("{", m.end())
        end = opened
        while 0 <= end < len(code) - 1 and depths[end + 1] > 0:
            end += 1
        triples.append((m.group(1), m.group(2), code[m.start() : end + 1 if opened >= 0 else len(code)]))
    return triples


def test_targets(root: Path) -> dict[str, str]:
    """Maps each Tests/ folder name to the test target that compiles it, read from the project."""
    project = (root / "WorkoutTracker.xcodeproj/project.pbxproj").read_text()
    targets: dict[str, str] = {}
    for block in re.findall(r"isa = PBXNativeTarget;(.*?)\n\t\t\};", project, re.DOTALL):
        name = re.search(r"\bname = (\w+);", block)
        groups = re.search(r"fileSystemSynchronizedGroups = \((.*?)\);", block, re.DOTALL)
        if name and groups and name.group(1).endswith("Tests"):
            for folder in re.findall(r"/\* (\w+) \*/", groups.group(1)):
                targets.setdefault(folder, name.group(1))
    return targets


class Index:
    def __init__(self, root: Path):
        targets = test_targets(root)
        self.code: dict[str, str] = {}
        self.suites: dict[str, list[str]] = {}
        self.target: dict[str, str] = {}
        for top in ("App", "Sources", "Tests"):
            for path in sorted((root / top).rglob("*.swift")):
                rel = path.relative_to(root).as_posix()
                self.code[rel] = COMMENT.sub("", path.read_text(errors="replace"))
                if top == "Tests":
                    target = self.target[rel] = targets.get(rel.split("/")[1], "")
                    decls = declarations(self.code[rel])
                    suites = [f"{target}/{n}" for _, n, body in decls if target and TEST_MARK.search(body)]
                    suites += [f"{target}/{n}()" for n in global_tests(self.code[rel]) if target]
                    self.suites[rel] = list(dict.fromkeys(suites))
        self.declared = {
            n
            for rel, code in self.code.items()
            if not rel.startswith("Tests/")
            for kind, n, _ in declarations(code)
            if kind != "extension"
        }

    def names(self, rel: str) -> list[str]:
        return [n for kind, n, _ in declarations(self.code[rel]) if kind != "extension" or n in self.declared]

    def test_ids(self, name: str) -> set[str]:
        func = re.compile(r"func " + re.escape(name) + r"\(")
        found = set()
        for rel, suites in self.suites.items():
            found.update(s for s in suites if s.endswith(f"/{name}()"))
            for _, type_name, body in declarations(self.code[rel]):
                if f"{self.target[rel]}/{type_name}" in suites and func.search(body):
                    found.add(f"{self.target[rel]}/{type_name}/{name}")
        return found

    def users(self, rel: str, prefixes: tuple[str, ...]) -> set[str]:
        names = self.names(rel)
        ids = IDENTIFIER.findall(self.code[rel])
        words = re.compile(r"\b(?:" + "|".join(map(re.escape, names)) + r")\b") if names else None
        return {
            other
            for other, code in self.code.items()
            if other != rel
            and other.startswith(prefixes)
            and ((words and words.search(code)) or any(f'"{i}' in code for i in ids))
        }

    def suites_naming(self, files: set[str]) -> set[str]:
        found: set[str] = set()
        seen, frontier = set(files), set(files)
        while frontier:
            hits = set()
            for rel in frontier:
                # A helper outside Tests/Support compiles only into its own folder's target.
                helper = rel.startswith("Tests/") and not rel.startswith("Tests/Support/")
                hits |= self.users(rel, (rel.rsplit("/", 1)[0] + "/",) if helper else ("Tests/",))
            hits -= seen
            seen |= hits
            found.update(s for rel in hits for s in self.suites[rel])
            frontier = {rel for rel in hits if not self.suites[rel]}
        return found

    def covering(self, rel: str) -> tuple[set[str], list[str]]:
        if rel not in self.code:
            return set(), []
        if self.suites.get(rel):
            return set(self.suites[rel]), []
        frontier, seen = {rel}, {rel}
        while frontier:
            found = self.suites_naming(frontier)
            if found:
                return found, sorted(frontier - {rel})
            containers = set()
            for f in frontier:
                # Sources/ cannot import App/, so an App/ type is used only in App/.
                containers |= self.users(f, ("App/",) if f.startswith("App/") else ("App/", "Sources/"))
            frontier = containers - seen
            seen |= frontier
        return set(), []


def changed_files(root: Path, base: str) -> list[str]:
    def git(*args: str) -> str:
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=True).stdout

    try:
        fork = git("merge-base", base, "HEAD").strip()
    except subprocess.CalledProcessError:
        print(f"error: git cannot find where HEAD left '{base}'.", file=sys.stderr)
        sys.exit(2)
    names = git("diff", "--name-only", "--diff-filter=d", fork, "--", "*.swift").split()
    names += git("ls-files", "--others", "--exclude-standard", "--", "*.swift").split()
    return sorted(set(names))


def main(argv: list[str]) -> int:
    if argv[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    base, args = "origin/main", []
    while argv:
        arg = argv.pop(0)
        if arg == "--base" and argv:
            base = argv.pop(0)
        elif arg.startswith("-"):
            print(__doc__.strip(), file=sys.stderr)
            return 2
        else:
            args.append(arg)
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode != 0:
        print("error: run inside the repository.", file=sys.stderr)
        return 2
    root = Path(top.stdout.strip())
    index = Index(root)
    ids: set[str] = set()
    tests = [a for a in args if re.fullmatch(r"\w+", a)]
    for name in tests:
        found = index.test_ids(name)
        if not found:
            print(f"tests-for: no suite declares func {name}", file=sys.stderr)
        ids |= found
    files = [os.path.relpath(Path(a).resolve(), root.resolve()) for a in args if a not in tests]
    files = files if args else changed_files(root, base)
    for rel in files:
        found, via = index.covering(rel)
        if not found and rel.startswith("App/"):
            print(f"tests-for: no suite reaches {rel}; every WorkoutTrackerUITests test launches the app", file=sys.stderr)
        elif not found:
            print(f"tests-for: no suite covers {rel}", file=sys.stderr)
        elif via:
            print(f"tests-for: no suite names {rel}, so these are the suites of {', '.join(via)}", file=sys.stderr)
        ids |= found
    for test_id in sorted(ids):
        print(test_id)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
