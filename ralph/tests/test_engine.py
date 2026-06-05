from __future__ import annotations

import unittest
from pathlib import Path

from ralph.orchestrator.engine import Engine, FakeEngine, PhaseRequest, build_engine
from ralph.orchestrator.phase import PhaseResult, PhaseStatus


def _request(phase: str = "implement") -> PhaseRequest:
    return PhaseRequest(
        phase=phase,
        prompt="do the work",
        workdir=Path("/tmp/worktree"),
        issue_number=206,
        timeout_seconds=10,
    )


class FakeEngineTests(unittest.TestCase):
    def test_default_phase_is_complete(self) -> None:
        result = FakeEngine().run_phase(_request())
        self.assertIs(result.status, PhaseStatus.COMPLETE)

    def test_is_an_engine(self) -> None:
        self.assertIsInstance(FakeEngine(), Engine)

    def test_records_every_call_in_order(self) -> None:
        engine = FakeEngine()
        engine.run_phase(_request("a"))
        engine.run_phase(_request("b"))
        self.assertEqual([call.phase for call in engine.calls], ["a", "b"])

    def test_scripted_status_per_phase(self) -> None:
        engine = FakeEngine(results_by_phase={"ui-verify": PhaseStatus.BLOCKED})
        result = engine.run_phase(_request("ui-verify"))
        self.assertIs(result.status, PhaseStatus.BLOCKED)
        self.assertIsNotNone(result.blocked_reason)

    def test_scripted_full_result_is_returned_verbatim(self) -> None:
        canned = PhaseResult(phase="x", status=PhaseStatus.TIMEOUT, final_response="boom")
        engine = FakeEngine(results_by_phase={"x": canned})
        self.assertIs(engine.run_phase(_request("x")), canned)

    def test_default_status_override(self) -> None:
        engine = FakeEngine(default_status=PhaseStatus.FAILED)
        self.assertIs(engine.run_phase(_request()).status, PhaseStatus.FAILED)


class BuildEngineTests(unittest.TestCase):
    def test_fake_engine_is_available(self) -> None:
        self.assertIsInstance(build_engine("fake"), FakeEngine)

    def test_real_engines_are_not_available_yet(self) -> None:
        for name in ("claude", "codex", "claude-cli", "codex-cli"):
            with self.assertRaises(NotImplementedError):
                build_engine(name)


if __name__ == "__main__":
    unittest.main()
