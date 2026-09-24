#!/usr/bin/env python3
"""The accessibility tree as text, and the owner of the tree line format.

Reads an `axe describe-ui` JSON tree on stdin:
  tree.py flat [--all]   one line per labeled or identified element: role, id, label, value, @x,y wxh
                         on-screen elements only; --all keeps the off-screen ones too
  tree.py find <id>      that element's line wherever it is, on screen or off; exit 1 if absent
                         says on stderr when it is off-screen, clipped (its centre outside the frame
                         of an ancestor of nonzero size), or disabled
  tree.py tappable <id>  "x y" of the first hit that is enabled, on screen, and not clipped, so a tap
                         on it lands; exit 1 with the same notes find prints when there is no such hit
  tree.py tappable --label TEXT
                         the same for the one element labelled exactly TEXT, a control over a text with
                         that label; exit 1 listing each with its centre when more than one is left
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
from typing import Any, Iterator, List, NamedTuple, Optional, Tuple


def clean(field: Any) -> str:
    if field is None:
        return ""
    return str(field).replace("\t", " ").replace("\n", " ")


class Frame(NamedTuple):
    x: float
    y: float
    width: float
    height: float

    @classmethod
    def of(cls, node: dict) -> "Frame":
        frame = node["frame"]
        return cls(frame["x"], frame["y"], frame["width"], frame["height"])

    @property
    def text(self) -> str:
        return f"@{self.x:.0f},{self.y:.0f} {self.width:.0f}x{self.height:.0f}"

    @property
    def center(self) -> Tuple[float, float]:
        return self.x + self.width / 2, self.y + self.height / 2

    def intersects(self, other: "Frame") -> bool:
        return (
            self.x < other.x + other.width and self.x + self.width > other.x
            and self.y < other.y + other.height and self.y + self.height > other.y
        )

    def covers(self, other: "Frame") -> bool:
        return (
            self.x <= other.x and self.x + self.width >= other.x + other.width
            and self.y <= other.y and self.y + self.height >= other.y + other.height
        )

    def holds(self, point: Tuple[float, float]) -> bool:
        x, y = point
        return self.x <= x < self.x + self.width and self.y <= y < self.y + self.height


def clipper(frame: Frame, ancestors: Tuple[dict, ...], screen: Frame) -> Optional[str]:
    for ancestor in reversed(ancestors):
        bounds = Frame.of(ancestor)
        if bounds.width == 0 or bounds.height == 0 or bounds.covers(screen) or bounds.holds(frame.center):
            continue
        name = clean(ancestor.get("AXUniqueId") or ancestor.get("AXLabel"))
        return " ".join(part for part in (clean(ancestor.get("role")), name, bounds.text) if part)
    return None


class TreeLine(NamedTuple):
    role: str
    ident: str
    label: str
    value: str
    frame: Frame
    enabled: bool
    clipped_by: Optional[str]

    @classmethod
    def from_node(cls, node: dict, ancestors: Tuple[dict, ...], screen: Frame) -> Optional["TreeLine"]:
        ident, label = node.get("AXUniqueId"), node.get("AXLabel")
        if not (ident or label):
            return None
        frame = Frame.of(node)
        return cls(
            clean(node.get("role")), clean(ident), clean(label), clean(node.get("AXValue")), frame,
            node.get("enabled") is not False, clipper(frame, ancestors, screen),
        )

    @property
    def text(self) -> str:
        return f"{self.role}\t{self.ident}\t{self.label}\t{self.value}\t{self.frame.text}"


class Diff(NamedTuple):
    hunks: List[List[str]]
    unchanged: int


def identity(text_line: str) -> str:
    return text_line.rsplit("\t", 1)[0]


def walk(node: dict, ancestors: Tuple[dict, ...] = ()) -> Iterator[Tuple[dict, Tuple[dict, ...]]]:
    yield node, ancestors
    for child in node.get("children", []):
        yield from walk(child, ancestors + (node,))


def lines(root: dict) -> List[TreeLine]:
    screen = Frame.of(root)
    built = (TreeLine.from_node(node, ancestors, screen) for node, ancestors in walk(root))
    return [line for line in built if line is not None]


def on_screen(all_lines: List[TreeLine], screen: Frame) -> List[TreeLine]:
    return [line for line in all_lines if line.frame.intersects(screen)]


def by_id(root: dict, ident: str) -> List[TreeLine]:
    return [line for line in lines(root) if line.ident == ident]


def by_label(root: dict, label: str) -> List[TreeLine]:
    wanted = label.strip()
    if not wanted:
        return []
    return [line for line in lines(root) if line.label.strip() == wanted]


# The roles of axe 1.8.0's actionableTypes, which break a tie between elements that share a label.
CONTROLS = frozenset({
    "AXButton", "AXCell", "AXCheckBox", "AXLink", "AXMenuItem", "AXPopUpButton", "AXRadioButton",
    "AXSecureTextField", "AXSegmentedControl", "AXSlider", "AXSwitch", "AXTab", "AXTabBarButton",
    "AXTextField", "AXToggle",
})


def tap_candidates(matches: List[TreeLine]) -> List[TreeLine]:
    controls = [line for line in matches if line.role in CONTROLS]
    return controls or matches


def obstacles(found: List[TreeLine], screen: Frame) -> List[str]:
    notes = []
    if any(not line.frame.intersects(screen) for line in found):
        notes.append("off-screen: swipe it into view before tapping")
    for ancestor in dict.fromkeys(line.clipped_by for line in found if line.clipped_by is not None):
        notes.append(f"clipped: outside {ancestor}; bring it inside that frame before tapping")
    if not all(line.enabled for line in found):
        notes.append("disabled: a tap on it does nothing")
    return notes


def changed(before: List[str], after: List[str]) -> Diff:
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
    return Diff(hunks, same)


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
    hunks, unchanged = changed(read_tree(a_path), read_tree(b_path))
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
    print(f"{count} changed, {unchanged} unchanged")


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "diff":
        diff(sys.argv[2], sys.argv[3])
        return
    if mode not in ("pid", "frame", "flat", "find", "tappable", "center"):
        sys.exit(__doc__)
    root = json.load(sys.stdin)[0]
    screen = Frame.of(root)
    if mode == "pid":
        print(root["pid"])
    elif mode == "frame":
        print(f"{screen.width:.0f} {screen.height:.0f}")
    elif mode == "flat":
        every = lines(root)
        shown = every if "--all" in sys.argv[2:] else on_screen(every, screen)
        for line in shown:
            print(line.text)
        hidden = len(every) - len(shown)
        if hidden:
            print(f"{hidden} off-screen elements hidden; `verify.sh tree --all` lists them", file=sys.stderr)
    elif mode == "find":
        found = by_id(root, sys.argv[2])
        if not found:
            sys.exit(1)
        for line in found:
            print(line.text)
        for note in obstacles(found, screen):
            print(note, file=sys.stderr)
    elif mode == "tappable":
        if sys.argv[2] == "--label":
            label = sys.argv[3]
            found = tap_candidates(by_label(root, label))
            if len(found) > 1:
                listed = [f"{len(found)} elements labelled {label} could take this tap; "
                          "pick one by its id, or tap its centre with -x -y:"]
                for line in found:
                    x, y = line.frame.center
                    listed.append(f"{line.text}\t-x {x:.0f} -y {y:.0f}")
                sys.exit("\n".join(listed))
            if not found:
                sys.exit(f"no element with label {label}")
        else:
            found = by_id(root, sys.argv[2])
            if not found:
                sys.exit(f"no element with id {sys.argv[2]}")
        for line in found:
            if not obstacles([line], screen):
                x, y = line.frame.center
                print(f"{x:.0f} {y:.0f}")
                return
        sys.exit("\n".join(obstacles(found, screen)))
    elif mode == "center":
        for line in lines(root):
            if line.ident == sys.argv[2]:
                x, y = line.frame.center
                print(f"{x:.0f} {y:.0f}")
                return
        sys.exit(1)


main()
