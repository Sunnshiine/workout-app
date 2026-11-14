import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import foreground  # noqa: E402


class Clock:
    """Each CPU-time read spends 1/16 s of CPU and RATIO times that of wall time, so every run of the probe reads
    wall/cpu RATIO exactly. Sixteenths keep the sums exact in binary, so a ratio of 2.0 reads 2.0, not 2.0000001."""

    STEP = 0.0625

    def __init__(self, ratio):
        self.ratio, self.wall, self.cpu = ratio, 0.0, 0.0

    def monotonic(self):
        return self.wall

    def process_time(self):
        self.cpu += self.STEP
        self.wall += self.STEP * self.ratio
        return self.cpu


class Threshold(unittest.TestCase):
    def probe(self, ratio):
        clock, out = Clock(ratio), io.StringIO()
        with mock.patch.object(foreground.time, "monotonic", clock.monotonic), \
                mock.patch.object(foreground.time, "process_time", clock.process_time), \
                contextlib.redirect_stdout(out), self.assertRaises(SystemExit) as exit:
            foreground.main()
        return exit.exception.code, out.getvalue()

    def test_a_foreground_given_three_times_its_cpu_in_wall_time_is_starved_and_exits_3(self):
        self.assertEqual(self.probe(3.0), (3, "starved (wall/cpu 3.00)\n"))

    def test_a_foreground_that_gets_its_cpu_is_ok_and_exits_0(self):
        self.assertEqual(self.probe(1.0), (0, "ok (wall/cpu 1.00)\n"))

    def test_a_ratio_of_exactly_the_limit_is_still_ok(self):
        self.assertEqual(self.probe(2.0), (0, "ok (wall/cpu 2.00)\n"))

    def test_a_ratio_just_over_the_limit_is_starved(self):
        self.assertEqual(self.probe(2.125), (3, "starved (wall/cpu 2.12)\n"))


if __name__ == "__main__":
    unittest.main()
