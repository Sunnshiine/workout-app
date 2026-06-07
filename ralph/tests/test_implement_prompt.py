from __future__ import annotations

import unittest
from pathlib import Path

IMPLEMENT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "implement.md"
REVIEW_PATH = Path(__file__).resolve().parents[1] / "prompts" / "review.md"
DIAGNOSE_PATH = Path(__file__).resolve().parents[1] / "prompts" / "diagnose.md"


class GithubContractDiscoveryTests(unittest.TestCase):
    def test_implement_excludes_gh_issue_view(self) -> None:
        prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")
        self.assertNotIn("gh issue view", prompt)

    def test_implement_excludes_agent_brief_authority(self) -> None:
        prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")
        self.assertNotIn("Agent Brief", prompt)

    def test_review_excludes_gh_issue_view(self) -> None:
        prompt = REVIEW_PATH.read_text(encoding="utf-8")
        self.assertNotIn("gh issue view", prompt)

    def test_diagnose_retains_gh_issue_view(self) -> None:
        prompt = DIAGNOSE_PATH.read_text(encoding="utf-8")
        self.assertIn("gh issue view", prompt)


class ImplementMinimalTemplateTests(unittest.TestCase):
    """implement.md is the minimal template plus one conditional domain line (#285)."""

    def setUp(self) -> None:
        self.prompt = IMPLEMENT_PATH.read_text(encoding="utf-8")

    def test_does_not_restate_allowed_or_forbidden_action_lists(self) -> None:
        # The controller-injected envelope owns <allowed_actions>/<forbidden_actions>;
        # the body must not restate concrete forbidden/allowed phrases.
        lower = self.prompt.lower()
        self.assertNotIn("xcode ui integration target", lower)
        self.assertNotIn("workouttrackeruitests", lower)
        self.assertNotIn("ui interaction suite", lower)
        self.assertNotIn("visual regression", lower)
        self.assertNotIn("reviewer subagents", lower)

    def test_no_unconditional_doc_reading_checklist(self) -> None:
        # Only the frozen contract is unconditional authority; AGENTS.md/CLAUDE.md
        # and PRD reads are not part of the minimal body.
        self.assertNotIn("AGENTS.md", self.prompt)
        self.assertNotIn("CLAUDE.md", self.prompt)
        self.assertNotIn("PRD", self.prompt)

    def test_contains_conditional_context_md_line(self) -> None:
        self.assertIn("CONTEXT.md", self.prompt)
        self.assertIn("ADR", self.prompt)

    def test_contract_is_the_authority(self) -> None:
        self.assertIn("Issue contract is the source of truth", self.prompt)

    def test_no_mandatory_observations_block(self) -> None:
        self.assertNotIn("<observations>", self.prompt)
        self.assertNotIn("observations block", self.prompt.lower())

    def test_no_xml_envelope_tags_in_body(self) -> None:
        # The envelope wraps the body; the body itself stays plain prose.
        for tag in ("<role>", "<contract>", "<work>", "<completion_gate>"):
            self.assertNotIn(tag, self.prompt)

    def test_mentions_blocked_outcome(self) -> None:
        self.assertIn("BLOCKED", self.prompt)

    def test_is_minimal_in_length(self) -> None:
        non_blank_lines = [line for line in self.prompt.splitlines() if line.strip()]
        self.assertLessEqual(len(non_blank_lines), 12)


if __name__ == "__main__":
    unittest.main()
