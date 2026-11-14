#!/usr/bin/env python3
"""Whether this host gives a foreground job the CPU to film by: 20 runs of 100 ms of CPU work, and
the median of each run's wall time over its CPU time.

Prints `ok (wall/cpu 1.02)` and exits 0 at LIMIT or under, or `starved (wall/cpu 2.70)` and exits 3.

The 1-minute load does not say this. The median read 1.01 to 1.03 at loads of 57 to 130, and 2.7 at
loads of 383 to 520. LIMIT is provisional: no take has yet been filmed between those bands.
"""
import sys
import time

LIMIT = 2.0


def main() -> None:
    ratios = []
    for _ in range(20):
        wall, cpu = time.monotonic(), time.process_time()
        while time.process_time() - cpu < 0.1:
            pass
        ratios.append((time.monotonic() - wall) / (time.process_time() - cpu))
    median = sorted(ratios)[10]
    starved = median > LIMIT
    print("%s (wall/cpu %.2f)" % ("starved" if starved else "ok", median))
    sys.exit(3 if starved else 0)


if __name__ == "__main__":
    main()
