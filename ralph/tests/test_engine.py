from __future__ import annotations

import unittest
from pathlib import Path

from ralph.orchestrator.engine import Engine, FakeEngine, PhaseRequest, build_engine
from ralph.orchestrator.engines import (
    ClaudeCliEngine,
    CodexCliEngine,
)
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

    def test_cli_engines_resolve_to_cli_adapters(self) -> None:
        self.assertIsInstance(build_engine("codex-cli"), CodexCliEngine)
        self.assertIsInstance(build_engine("claude-cli"), ClaudeCliEngine)

    def test_sdk_engines_fall_back_to_cli_without_a_client(self) -> None:
        # build_engine wires no provider client, so SDK names degrade to the
        # proven CLI fallback rather than failing hard during the migration.
        self.assertIsInstance(build_engine("codex"), CodexCliEngine)
        self.assertIsInstance(build_engine("claude"), ClaudeCliEngine)

    def test_unknown_engine_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            build_engine("nope")


if __name__ == "__main__":
    unittest.main()
