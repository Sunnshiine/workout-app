from __future__ import annotations

import unittest
from pathlib import Path

IMPLEMENT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "implement.md"
UI_VERIFY_PATH = Path(__file__).resolve().parents[1] / "prompts" / "ui-verify.md"
REVIEW_PATH = Path(__file__).resolve().parents[1] / "prompts" / "review.md"
DIAGNOSE_PATH = Path(__file__).resolve().parents[1] / "prompts" / "diagnose.md"


class GithubContractDiscoveryTests(unittest.TestCase):
    def test_implement_excludes_gh_issue_view(self) -> None:
        prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")
        self.assertNotIn("gh issue view", prompt)

    def test_implement_excludes_agent_brief_authority(self) -> None:
        prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")
        self.assertNotIn("Agent Brief", prompt)

    def test_implement_uses_local_context_artifacts(self) -> None:
        prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")
        self.assertIn("CONTEXT_PATH", prompt)

    def test_ui_verify_excludes_gh_issue_view(self) -> None:
        prompt = UI_VERIFY_PATH.read_text(encoding="utf-8")
        self.assertNotIn("gh issue view", prompt)

    def test_ui_verify_excludes_agent_brief_authority(self) -> None:
        prompt = UI_VERIFY_PATH.read_text(encoding="utf-8")
        self.assertNotIn("Agent Brief", prompt)

    def test_ui_verify_uses_local_context_artifacts(self) -> None:
        prompt = UI_VERIFY_PATH.read_text(encoding="utf-8")
        self.assertIn("CONTEXT_PATH", prompt)

    def test_review_excludes_gh_issue_view(self) -> None:
        prompt = REVIEW_PATH.read_text(encoding="utf-8")
        self.assertNotIn("gh issue view", prompt)

    def test_diagnose_retains_gh_issue_view(self) -> None:
        prompt = DIAGNOSE_PATH.read_text(encoding="utf-8")
        self.assertIn("gh issue view", prompt)


class ImplementPhaseUIBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")

    def test_implement_permits_visual_regression_tests(self) -> None:
        self.assertIn("Visual Regression", self.prompt)

    def test_implement_does_not_broadly_forbid_ui_tests(self) -> None:
        # Must not use the broad phrase that bans all UI tests
        self.assertNotIn("Do NOT run Xcode UI integration tests in this phase", self.prompt)
        self.assertNotIn("do not run UI tests", self.prompt.lower())

    def test_implement_forbids_full_xcode_ui_integration_target(self) -> None:
        lower = self.prompt.lower()
        self.assertIn("xcode ui integration target", lower)

    def test_implement_forbids_full_workouttrackertests_bundle(self) -> None:
        self.assertIn("WorkoutTrackerUITests", self.prompt)

    def test_implement_forbids_ui_interaction_suite(self) -> None:
        self.assertIn("UI Interaction Suite", self.prompt)

    def test_implement_completion_gate_does_not_broadly_exclude_ui_tests(self) -> None:
        # The completion gate must not say "You did not run UI tests"
        lower = self.prompt.lower()
        self.assertNotIn("you did not run ui tests", lower)
        self.assertNotIn("did not run ui tests", lower)


if __name__ == "__main__":
    unittest.main()
