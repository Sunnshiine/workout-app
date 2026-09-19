#!/usr/bin/env python3
"""The accessibility tree as text. Owns the tree line format; nothing else parses it.

Reads an `axe describe-ui` JSON tree on stdin:
  tree.py flat [--all]   one line per labeled or identified element: role, id, label, value, @x,y wxh
                         on-screen elements only; --all keeps the off-screen ones too
  tree.py find <id>      that element's line wherever it is, on screen or off; exit 1 if absent
  tree.py pid            the frontmost application's pid
  tree.py frame          the application's width and height
  tree.py center <id>    "x y" of the element with that accessibility identifier; exit 1 if absent

Reads two saved trees:
  tree.py diff A.tree.txt B.tree.txt   the lines that changed, frames ignored
"""
import difflib
import json
import sys
from pathlib import Path
from typing import Iterator, List, NamedTuple, Optional, Tuple


def clean(field) -> str:
    """Tabs and newlines become spaces here, so every line splits into exactly five columns."""
    if field is None:
        return ""
    return str(field).replace("\t", " ").replace("\n", " ")


class TreeLine(NamedTuple):
    """One element. role, ident, label and value are its identity; the frame is position only."""

    role: str
    ident: str
    label: str
    value: str
    x: float
    y: float
    width: float
    height: float

    @classmethod
    def from_node(cls, node: dict) -> Optional["TreeLine"]:
        ident, label = node.get("AXUniqueId"), node.get("AXLabel")
        if not (ident or label):
            return None
        frame = node["frame"]
        return cls(
            clean(node.get("role")), clean(ident), clean(label), clean(node.get("AXValue")),
            frame["x"], frame["y"], frame["width"], frame["height"],
        )

    @property
    def text(self) -> str:
        return (
            f"{self.role}\t{self.ident}\t{self.label}\t{self.value}"
            f"\t@{self.x:.0f},{self.y:.0f} {self.width:.0f}x{self.height:.0f}"
        )

    @property
    def center(self) -> Tuple[float, float]:
        return self.x + self.width / 2, self.y + self.height / 2

    def intersects(self, other: "TreeLine") -> bool:
        return (
            self.x <= other.x + other.width and self.x + self.width >= other.x
            and self.y <= other.y + other.height and self.y + self.height >= other.y
        )


def identity(text_line: str) -> str:
    """A saved line without its frame column: everything before the last tab."""
    return text_line.rsplit("\t", 1)[0]


def walk(node: dict) -> Iterator[dict]:
    yield node
    for child in node.get("children", []):
        yield from walk(child)


def lines(root: dict) -> List[TreeLine]:
    """Every line in document order. lines(root)[0] is the AXApplication row: the screen."""
    return [line for line in map(TreeLine.from_node, walk(root)) if line is not None]


def on_screen(all_lines: List[TreeLine]) -> List[TreeLine]:
    """The lines whose frame intersects the screen, edges included.

    The screen comes from the data, so iPad, landscape, and a future device need no constant.
    Occlusion is invisible to it: with the queue sheet up, the stage rows behind it stay.
    """
    if not all_lines:
        return []
    return [line for line in all_lines if line.intersects(all_lines[0])]


def changed(before: List[str], after: List[str]) -> Tuple[List[List[str]], int]:
    """Hunks of "- line" and "+ line" in document order, and the count of unchanged lines.

    Sequence-based, not set-based: a tree repeats lines (two `Vertical scroll bar` rows with the
    queue sheet up) and their order carries meaning.
    """
    matcher = difflib.SequenceMatcher(
        a=[identity(line) for line in before], b=[identity(line) for line in after], autojunk=False
    )
    hunks = []
    same = 0
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            same += i2 - i1
            continue
        hunks.append(["- " + line for line in before[i1:i2]] + ["+ " + line for line in after[j1:j2]])
    return hunks, same


def read_tree(path: str) -> List[str]:
    try:
        return Path(path).read_text(encoding="utf-8").splitlines()
    except OSError as error:
        print(f"cannot read {path}: {error.strerror}", file=sys.stderr)
        sys.exit(66)


def shot_name(path: str) -> str:
    name = Path(path).name
    return name[: -len(".tree.txt")] if name.endswith(".tree.txt") else name


def diff(a_path: str, b_path: str) -> None:
    hunks, same = changed(read_tree(a_path), read_tree(b_path))
    a_name, b_name = shot_name(a_path), shot_name(b_path)
    if not hunks:
        print(f"no tree changes from {a_name} to {b_name}, frames ignored")
        return
    print(f"changed from {a_name} to {b_name}, frames ignored:")
    count = 0
    for hunk in hunks:
        for line in hunk:
            print(line)
        print()
        count += len(hunk)
    print(f"{count} changed, {same} unchanged")


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "diff":
        diff(sys.argv[2], sys.argv[3])
        return
    root = json.load(sys.stdin)[0]
    if mode == "pid":
        print(root["pid"])
    elif mode == "frame":
        f = root["frame"]
        print(f"{f['width']:.0f} {f['height']:.0f}")
    elif mode == "flat":
        every = lines(root)
        shown = every if "--all" in sys.argv[2:] else on_screen(every)
        for line in shown:
            print(line.text)
        hidden = len(every) - len(shown)
        if hidden:
            print(f"{hidden} off-screen elements hidden; `verify.sh tree --all` lists them", file=sys.stderr)
    elif mode == "find":
        every = lines(root)
        hits = [line for line in every if line.ident == sys.argv[2]]
        if not hits:
            sys.exit(1)
        for line in hits:
            print(line.text)
        if any(not line.intersects(every[0]) for line in hits):
            print("off-screen: swipe it into view before tapping", file=sys.stderr)
    elif mode == "center":
        for line in lines(root):
            if line.ident == sys.argv[2]:
                x, y = line.center
                print(f"{x:.0f} {y:.0f}")
                return
        sys.exit(1)
    else:
        sys.exit(__doc__)


main()
