from __future__ import annotations

import unittest
from pathlib import Path

from ralph.orchestrator.gates import (
    FAILURE_EXCERPT_LIMIT,
    GATE_SWIFT_TEST,
    GATE_UI_INTEGRATION,
    GATE_VISUAL_REGRESSION,
    CommandResult,
    GateRunner,
    GateSpec,
    GateStatus,
    failure_excerpt,
    is_ui_owned_gate,
)


def _runner(results: dict[str, CommandResult]):
    def run(command):
        # Look up by the gate command's terminal token for the fake.
        key = command[-1]
        return results[key]

    return run


class GateRunnerTests(unittest.TestCase):
    def test_passing_gate_is_passed_with_zero_exit(self) -> None:
        runner = GateRunner(lambda _c: CommandResult(exit_status=0, output="ok"))
        result = runner.run(GateSpec(name=GATE_SWIFT_TEST, command=("swift", "test")))
        self.assertEqual(result.status, GateStatus.PASSED)
        self.assertEqual(result.exit_status, 0)
        self.assertIsNone(result.failure_excerpt)
        self.assertFalse(result.ui_owned)

    def test_failing_gate_captures_exit_and_excerpt(self) -> None:
        runner = GateRunner(lambda _c: CommandResult(exit_status=65, output="boom failure"))
        result = runner.run(GateSpec(name=GATE_SWIFT_TEST, command=("swift", "test")))
        self.assertEqual(result.status, GateStatus.FAILED)
        self.assertEqual(result.exit_status, 65)
        self.assertEqual(result.failure_excerpt, "boom failure")

    def test_ui_integration_gate_is_ui_owned(self) -> None:
        runner = GateRunner(lambda _c: CommandResult(exit_status=1, output="x"))
        result = runner.run(GateSpec(name=GATE_UI_INTEGRATION, command=("xcodebuild",)))
        self.assertTrue(result.ui_owned)

    def test_visual_regression_gate_is_ui_owned(self) -> None:
        self.assertTrue(is_ui_owned_gate(GATE_VISUAL_REGRESSION))

    def test_removed_screenshot_artifact_gate_is_not_ui_owned(self) -> None:
        self.assertFalse(is_ui_owned_gate("ui-screenshot-artifacts"))

    def test_removed_visual_baseline_authority_gate_is_not_ui_owned(self) -> None:
        self.assertFalse(is_ui_owned_gate("visual-baseline-authority"))

    def test_log_path_is_attached(self) -> None:
        logs = {GATE_SWIFT_TEST: Path("/logs/swift-test.log")}
        runner = GateRunner(
            lambda _c: CommandResult(exit_status=0),
            log_path_for=logs.get,
        )
        result = runner.run(GateSpec(name=GATE_SWIFT_TEST, command=("swift", "test")))
        self.assertEqual(result.log_path, Path("/logs/swift-test.log"))

    def test_run_all_stops_at_first_failure_and_skips_rest(self) -> None:
        results = {
            "test": CommandResult(exit_status=0),
            "generate": CommandResult(exit_status=1, output="gen failed"),
            "lint": CommandResult(exit_status=0),
        }
        runner = GateRunner(_runner(results))
        specs = [
            GateSpec(name="swift-test", command=("swift", "test")),
            GateSpec(name="xcodegen", command=("xcodegen", "generate")),
            GateSpec(name="lint", command=("swiftlint", "lint")),
        ]
        outcomes = runner.run_all(specs)
        statuses = [o.status for o in outcomes]
        self.assertEqual(
            statuses,
            [GateStatus.PASSED, GateStatus.FAILED, GateStatus.SKIPPED],
        )
        self.assertIsNone(outcomes[2].exit_status)


class FailureExcerptTests(unittest.TestCase):
    def test_empty_output_is_none(self) -> None:
        self.assertIsNone(failure_excerpt("   \n  "))

    def test_short_output_is_returned_whole(self) -> None:
        self.assertEqual(failure_excerpt("short error"), "short error")

    def test_long_output_is_tail_bounded(self) -> None:
        text = "A" * (FAILURE_EXCERPT_LIMIT + 500) + "TAIL"
        excerpt = failure_excerpt(text)
        self.assertEqual(len(excerpt), FAILURE_EXCERPT_LIMIT)
        self.assertTrue(excerpt.endswith("TAIL"))


if __name__ == "__main__":
    unittest.main()
