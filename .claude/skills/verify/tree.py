#!/usr/bin/env python3
"""Reads an `axe describe-ui` JSON tree on stdin.

  tree.py flat            one line per labeled or identified element: role, id, label, value, @x,y wxh
  tree.py pid             the frontmost application's pid
  tree.py frame           the application's width and height
  tree.py center <id>     "x y" of the element with that accessibility identifier; exit 1 if absent
"""
import json
import sys


def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)


def main():
    mode = sys.argv[1]
    root = json.load(sys.stdin)[0]
    if mode == "pid":
        print(root["pid"])
    elif mode == "frame":
        f = root["frame"]
        print(f"{f['width']:.0f} {f['height']:.0f}")
    elif mode == "flat":
        for n in walk(root):
            ident, label, value = n.get("AXUniqueId"), n.get("AXLabel"), n.get("AXValue")
            if not (ident or label):
                continue
            f = n["frame"]
            print(
                f"{n.get('role')}\t{ident or ''}\t{label or ''}\t{'' if value is None else value}"
                f"\t@{f['x']:.0f},{f['y']:.0f} {f['width']:.0f}x{f['height']:.0f}"
            )
    elif mode == "center":
        for n in walk(root):
            if n.get("AXUniqueId") == sys.argv[2]:
                f = n["frame"]
                print(f"{f['x'] + f['width'] / 2:.0f} {f['y'] + f['height'] / 2:.0f}")
                return
        sys.exit(1)
    else:
        sys.exit(__doc__)


main()
