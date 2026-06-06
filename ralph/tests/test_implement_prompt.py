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


if __name__ == "__main__":
    unittest.main()
