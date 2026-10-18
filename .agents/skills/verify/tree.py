#!/usr/bin/env python3
"""The accessibility tree as text, and the owner of the tree line format.

Reads an `axe describe-ui` JSON tree on stdin:
  tree.py flat [--all]   one line per labeled or identified element: role, id, label, value, @x,y wxh
                         on-screen elements only; --all keeps the off-screen ones and the elements
                         with neither id nor label too
  tree.py find <id>      that element's line wherever it is, on screen or off; exit 1 if absent
                         says on stderr when it is off-screen (no whole point on the screen), clipped
                         (its centre, or every point of it the screen shows, outside the frame of an
                         ancestor of nonzero size that does not cover the screen), or disabled
  tree.py frame-of <id>  the first such element's frame, as @x,y wxh, or none when the tree has no
                         such id; exit 0 either way, so any other exit is a tree it could not read
  tree.py tappable <id>  "x y" of the first hit that is enabled, on screen, and not clipped, so a tap
                         on it lands, then that hit's line; exit 1 with the same notes find prints when
                         there is no such hit. The point is the whole point nearest the centre of the
                         part of the hit the screen and its clipping ancestors show
  tree.py tappable --label TEXT
                         the same for the one element whose trimmed label is TEXT, a control over
                         a text with that label; exit 1 listing each with the point a tap takes when more
                         than one is left
  tree.py pid            the frontmost application's pid
  tree.py frame          the application's width and height
  tree.py center <id>    "x y" of the element with that accessibility identifier; exit 1 if absent

Reads a `describe-ui --point` answer on stdin (an object, a list led by it, or empty):
  tree.py landing LINE FRONT_PID X Y
                         exit 0 when the answer belongs to FRONT_PID, the tree's application, and is
                         LINE's element or lies within a point of LINE's frame; else exit 1 with a
                         covered: note naming X,Y, the point tapped

Reads saved trees:
  tree.py diff A.tree.txt B.tree.txt   the lines that changed, frames ignored
  tree.py crop SHOT.tree.txt PNG_WIDTH ID | crop SHOT.tree.txt PNG_WIDTH X Y W H
                         "px py pw ph X_Y_WxH": ID's frame grown by 8 points, or that rect in points,
                         clipped to the screen (the first line), in the PNG's pixels rounded outward,
                         then the clipped points; exit 1 when ID is absent or the rect is off the
                         screen, 2 on a malformed argument list
"""
import difflib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Iterator, List, NamedTuple, Optional, Tuple


def clean(field: Any) -> str:
    if field is None:
        return ""
    return str(field).replace("\t", " ").replace("\n", " ")


FRAME_TEXT = re.compile(r"@(-?\d+),(-?\d+) (\d+)x(\d+)")
PRINTED_FRAME_MARGIN = 1


class Frame(NamedTuple):
    x: float
    y: float
    width: float
    height: float

    @classmethod
    def of(cls, node: dict) -> "Frame":
        frame = node["frame"]
        return cls(frame["x"], frame["y"], frame["width"], frame["height"])

    @classmethod
    def parse(cls, text: str) -> "Frame":
        match = FRAME_TEXT.fullmatch(text)
        if match is None:
            raise ValueError(f"not a frame: {text}")
        return cls(*(int(side) for side in match.groups()))

    @property
    def text(self) -> str:
        return f"@{self.x:.0f},{self.y:.0f} {self.width:.0f}x{self.height:.0f}"

    def grown(self, by: float) -> "Frame":
        return Frame(self.x - by, self.y - by, self.width + 2 * by, self.height + 2 * by)

    @property
    def center(self) -> Tuple[float, float]:
        return self.x + self.width / 2, self.y + self.height / 2

    def covers(self, other: "Frame") -> bool:
        return (
            self.x <= other.x and self.x + self.width >= other.x + other.width
            and self.y <= other.y and self.y + self.height >= other.y + other.height
        )

    def holds(self, point: Tuple[float, float]) -> bool:
        x, y = point
        return self.x <= x < self.x + self.width and self.y <= y < self.y + self.height

    def overlap(self, other: "Frame") -> Optional["Frame"]:
        """The part of this frame inside other, or None when that part holds no whole point."""
        left, top = max(self.x, other.x), max(self.y, other.y)
        right = min(self.x + self.width, other.x + other.width)
        bottom = min(self.y + self.height, other.y + other.height)
        shared = Frame(left, top, right - left, bottom - top)
        return shared if whole_point(shared) is not None else None


Point = Tuple[int, int]


def whole_point(frame: Optional[Frame]) -> Optional[Point]:
    """The whole point the frame holds nearest its centre, since axe taps whole points."""
    if frame is None:
        return None
    point = []
    for start, size in ((frame.x, frame.width), (frame.y, frame.height)):
        first, last = math.ceil(start), math.ceil(start + size) - 1
        if first > last:
            return None
        point.append(min(max(round(start + size / 2), first), last))
    return point[0], point[1]


class Reach(NamedTuple):
    clipped_by: Optional[str]
    point: Optional[Point]


def reach(frame: Frame, ancestors: Tuple[dict, ...], screen: Frame) -> Reach:
    """The nearest ancestor that clips the element, and the point a tap on what is left of it takes.

    An ancestor clips when its frame misses every whole point of the element the screen and the
    nearer ancestors still show. It also clips when it misses the element's centre, the rule from
    before taps aimed at the visible part, kept for compatibility so `find` and `tappable` still
    refuse what they refused. One with a zero side, or one that covers the screen, never clips.
    """
    shown = frame.overlap(screen)
    clipped_by = None
    for ancestor in reversed(ancestors):
        bounds = Frame.of(ancestor)
        if bounds.width == 0 or bounds.height == 0 or bounds.covers(screen):
            continue
        left = shown and shown.overlap(bounds)
        if clipped_by is None and (not bounds.holds(frame.center) or (shown and not left)):
            name = clean(ancestor.get("AXUniqueId") or ancestor.get("AXLabel"))
            clipped_by = " ".join(part for part in (clean(ancestor.get("role")), name, bounds.text) if part)
        shown = left
    return Reach(clipped_by, whole_point(shown))


class TreeLine(NamedTuple):
    role: str
    ident: str
    label: str
    value: str
    frame: Frame
    enabled: bool
    clipped_by: Optional[str]
    on_screen: bool
    point: Optional[Point]

    @classmethod
    def from_node(cls, node: dict, ancestors: Tuple[dict, ...], screen: Frame) -> "TreeLine":
        ident, label = node.get("AXUniqueId"), node.get("AXLabel")
        frame = Frame.of(node)
        clipped_by, point = reach(frame, ancestors, screen)
        return cls(
            clean(node.get("role")), clean(ident), clean(label), clean(node.get("AXValue")), frame,
            node.get("enabled") is not False, clipped_by, frame.overlap(screen) is not None, point,
        )

    @classmethod
    def parse(cls, text_line: str) -> "TreeLine":
        role, ident, label, value, text = text_line.split("\t")
        frame = Frame.parse(text)
        return cls(role, ident, label, value, frame, True, None, True, None)

    @property
    def aim(self) -> Point:
        """Where a tap on it goes: its reachable point, or its frame centre when it has none."""
        if self.point is not None:
            return self.point
        x, y = self.frame.center
        return round(x), round(y)

    @property
    def named(self) -> bool:
        return bool(self.ident or self.label)

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


def every_line(root: dict) -> List[TreeLine]:
    screen = Frame.of(root)
    return [TreeLine.from_node(node, ancestors, screen) for node, ancestors in walk(root)]


def lines(root: dict) -> List[TreeLine]:
    return [line for line in every_line(root) if line.named]


def by_id(root: dict, ident: str) -> List[TreeLine]:
    return [line for line in lines(root) if line.ident == ident]


def by_label(root: dict, label: str) -> List[TreeLine]:
    wanted = label.strip()
    if not wanted:
        return []
    return [line for line in lines(root) if line.label.strip() == wanted]


AXE_ACTIONABLE_ROLES = frozenset({
    "AXButton", "AXCell", "AXCheckBox", "AXLink", "AXMenuItem", "AXPopUpButton", "AXRadioButton",
    "AXSecureTextField", "AXSegmentedControl", "AXSlider", "AXSwitch", "AXTab", "AXTabBarButton",
    "AXTextField", "AXToggle",
})


def tap_candidates(matches: List[TreeLine]) -> List[TreeLine]:
    controls = [line for line in matches if line.role in AXE_ACTIONABLE_ROLES]
    return controls or matches


def obstacles(found: List[TreeLine]) -> List[str]:
    notes = []
    if not all(line.on_screen for line in found):
        notes.append("off-screen: swipe it into view before tapping")
    for ancestor in dict.fromkeys(line.clipped_by for line in found if line.clipped_by is not None):
        notes.append(f"clipped: outside {ancestor}; bring it inside that frame before tapping")
    if not all(line.enabled for line in found):
        notes.append("disabled: a tap on it does nothing")
    return notes


def covered(target: TreeLine, answer: Any, front_pid: str, point: Point) -> Optional[str]:
    hit = answer[0] if isinstance(answer, list) and answer else answer
    if isinstance(hit, dict):
        hit_frame = Frame.of(hit)
        if str(hit.get("pid")) == front_pid and (
            (target.ident and hit.get("AXUniqueId") == target.ident) or target.frame.grown(PRINTED_FRAME_MARGIN).covers(hit_frame)
        ):
            return None
        name = clean(hit.get("AXUniqueId") or hit.get("AXLabel"))
        seen = " ".join(part for part in (clean(hit.get("role")), name, hit_frame.text) if part)
    else:
        seen = "nothing"
    x, y = point
    return (f"covered: at {x},{y} the screen has {seen}, not {target.role} {target.ident or target.label}; "
            "something is over it, or it left the screen after the tree was read")


CROP_PAD = 8
CROP_USAGE = "usage: tree.py crop SHOT.tree.txt PNG_WIDTH ID | crop SHOT.tree.txt PNG_WIDTH X Y W H"


def crop(args: List[str]) -> None:
    try:
        if len(args) not in (3, 6):
            raise ValueError
        tree_path, png_width = args[0], int(args[1])
        wanted = Frame(*(int(arg) for arg in args[2:])) if len(args) == 6 else None
        if png_width <= 0 or (wanted is not None and min(wanted.width, wanted.height) <= 0):
            raise ValueError
    except ValueError:
        print(CROP_USAGE, file=sys.stderr)
        sys.exit(2)
    shot = [TreeLine.parse(line) for line in read_tree(tree_path)]
    screen = shot[0].frame
    if wanted is None:
        found = next((line for line in shot if line.ident == args[2]), None)
        if found is None:
            ids = " ".join(dict.fromkeys(line.ident for line in shot if line.ident))
            sys.exit(f"no element {args[2]} on {shot_name(tree_path)}; its ids: {ids}")
        wanted = found.frame.grown(CROP_PAD)
    left, top = max(wanted.x, screen.x), max(wanted.y, screen.y)
    right = min(wanted.x + wanted.width, screen.x + screen.width)
    bottom = min(wanted.y + wanted.height, screen.y + screen.height)
    if right <= left or bottom <= top:
        sys.exit(f"{wanted.text} is off the {screen.width}x{screen.height} screen")
    px, py = left * png_width // screen.width, top * png_width // screen.width
    pw = -(-right * png_width // screen.width) - px
    ph = -(-bottom * png_width // screen.width) - py
    print(f"{px} {py} {pw} {ph} {left}_{top}_{right - left}x{bottom - top}")


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
    if mode == "crop":
        crop(sys.argv[2:])
        return
    if mode == "landing":
        if len(sys.argv) != 6:
            sys.exit(__doc__)
        answer = sys.stdin.read().strip()
        note = covered(TreeLine.parse(sys.argv[2]), json.loads(answer) if answer else None, sys.argv[3],
                       (int(sys.argv[4]), int(sys.argv[5])))
        if note:
            sys.exit(note)
        return
    if mode not in ("pid", "frame", "flat", "find", "frame-of", "tappable", "center"):
        sys.exit(__doc__)
    root = json.load(sys.stdin)[0]
    screen = Frame.of(root)
    if mode == "pid":
        print(root["pid"])
    elif mode == "frame":
        print(f"{screen.width:.0f} {screen.height:.0f}")
    elif mode == "flat":
        every = every_line(root)
        if "--all" in sys.argv[2:]:
            for line in every:
                print(line.text)
            return
        named = [line for line in every if line.named]
        shown = [line for line in named if line.on_screen]
        for line in shown:
            print(line.text)
        for count, kind in [(len(named) - len(shown), "off-screen elements"),
                            (len(every) - len(named), "elements with neither id nor label")]:
            if count:
                print(f"{count} {kind} hidden; `verify.sh tree --all` lists them", file=sys.stderr)
    elif mode == "find":
        found = by_id(root, sys.argv[2])
        if not found:
            sys.exit(1)
        for line in found:
            print(line.text)
        for note in obstacles(found):
            print(note, file=sys.stderr)
    elif mode == "frame-of":
        found = by_id(root, sys.argv[2])
        print(found[0].frame.text if found else "none")
    elif mode == "tappable":
        if sys.argv[2] == "--label":
            label = sys.argv[3]
            found = tap_candidates(by_label(root, label))
            if not found:
                sys.exit(f"no element with label {label}")
            if len(found) > 1:
                listed = [f"{len(found)} elements carry the label {label}; "
                          "pick one by its id, or tap it with -x -y:"]
                for line in found:
                    x, y = line.aim
                    listed.append(f"{line.text}\t-x {x} -y {y}")
                sys.exit("\n".join(listed))
        else:
            found = by_id(root, sys.argv[2])
            if not found:
                sys.exit(f"no element with id {sys.argv[2]}")
        for line in found:
            if line.point is not None and not obstacles([line]):
                x, y = line.point
                print(f"{x} {y}")
                print(line.text)
                return
        sys.exit("\n".join(obstacles(found)))
    elif mode == "center":
        for line in lines(root):
            if line.ident == sys.argv[2]:
                x, y = line.frame.center
                print(f"{x:.0f} {y:.0f}")
                return
        sys.exit(1)


if __name__ == "__main__":
    main()
