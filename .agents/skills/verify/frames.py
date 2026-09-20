#!/usr/bin/env python3
"""Names a burst's frames by when they were captured.

  frames.py DIR   renames DIR/f*.png to before.png or +NNNNms.png, timed from the mtime of
                  DIR/.drive-returned, and prints the new paths in capture order
"""
import os
import sys


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    directory = sys.argv[1]
    drive_returned = os.stat(os.path.join(directory, ".drive-returned")).st_mtime_ns
    for frame in sorted(f for f in os.listdir(directory) if f.startswith("f") and f.endswith(".png")):
        source = os.path.join(directory, frame)
        elapsed = (os.stat(source).st_mtime_ns - drive_returned) // 1000000
        target = os.path.join(directory, ("before" if elapsed < 0 else "+%04dms" % elapsed) + ".png")
        if os.path.exists(target):
            sys.exit("two frames share %s; run the burst again" % target)
        os.rename(source, target)
        print(target)


main()
