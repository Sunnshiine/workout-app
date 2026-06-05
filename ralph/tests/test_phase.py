from __future__ import annotations

import unittest

from ralph.orchestrator.phase import PhaseResult, PhaseStatus


class PhaseResultTests(unittest.TestCase):
    def test_complete_flag(self) -> None:
        result = PhaseResult(phase="implement", status=PhaseStatus.COMPLETE)
        self.assertTrue(result.is_complete)

    def test_blocked_is_not_complete(self) -> None:
        result = PhaseResult(
            phase="implement", status=PhaseStatus.BLOCKED, blocked_reason="missing tests"
        )
        self.assertFalse(result.is_complete)
        self.assertEqual(result.blocked_reason, "missing tests")

    def test_duration_seconds(self) -> None:
        result = PhaseResult(
            phase="p", status=PhaseStatus.COMPLETE, started_at=10.0, finished_at=15.5
        )
        self.assertEqual(result.duration_seconds, 5.5)

    def test_duration_none_when_timestamps_missing(self) -> None:
        result = PhaseResult(phase="p", status=PhaseStatus.COMPLETE)
        self.assertIsNone(result.duration_seconds)

    def test_status_str_is_wire_value(self) -> None:
        self.assertEqual(str(PhaseStatus.TIMEOUT), "timeout")
        self.assertEqual(PhaseStatus.FAILED.value, "failed")


if __name__ == "__main__":
    unittest.main()
