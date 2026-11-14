import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import foreground  # noqa: E402


class Clock:
    """Each CPU-time read spends 1/16 s of CPU and a run's ratio times that of wall time, so each run of the probe
    reads its ratio exactly. A run reads the CPU clock READS times, and run n gets ratios[n]. Sixteenths keep the
    sums exact in binary, so a ratio of 2.0 reads 2.0, not 2.0000001."""

    STEP = 0.0625
    READS = 4

    def __init__(self, ratios):
        self.ratios, self.reads, self.wall, self.cpu = ratios, 0, 0.0, 0.0

    def monotonic(self):
        return self.wall

    def process_time(self):
        ratio = self.ratios[min(self.reads // self.READS, len(self.ratios) - 1)]
        self.reads += 1
        self.cpu += self.STEP
        self.wall += self.STEP * ratio
        return self.cpu


class Threshold(unittest.TestCase):
    def probe(self, ratios):
        clock, out = Clock(ratios), io.StringIO()
        with mock.patch.object(foreground.time, "monotonic", clock.monotonic), \
                mock.patch.object(foreground.time, "process_time", clock.process_time), \
                contextlib.redirect_stdout(out), self.assertRaises(SystemExit) as exit:
            foreground.main()
        return exit.exception.code, out.getvalue()

    def test_a_foreground_given_three_times_its_cpu_in_wall_time_is_starved_and_exits_3(self):
        self.assertEqual(self.probe([3.0]), (3, "starved (wall/cpu 3.00)\n"))

    def test_a_foreground_that_gets_its_cpu_is_ok_and_exits_0(self):
        self.assertEqual(self.probe([1.0]), (0, "ok (wall/cpu 1.00)\n"))

    def test_a_ratio_of_exactly_the_limit_is_still_ok(self):
        self.assertEqual(self.probe([2.0]), (0, "ok (wall/cpu 2.00)\n"))

    def test_a_ratio_just_over_the_limit_is_starved(self):
        self.assertEqual(self.probe([2.125]), (3, "starved (wall/cpu 2.12)\n"))

    def test_a_host_that_starves_11_of_20_runs_is_starved_even_with_9_good_runs_among_them(self):
        self.assertEqual(self.probe([3.0] * 10 + [1.0] * 9 + [3.0]), (3, "starved (wall/cpu 3.00)\n"))

    def test_a_host_that_starves_9_of_20_runs_is_ok(self):
        self.assertEqual(self.probe([1.0] * 10 + [3.0] * 9 + [1.0]), (0, "ok (wall/cpu 1.00)\n"))


if __name__ == "__main__":
    unittest.main()
