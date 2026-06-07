from __future__ import annotations

import unittest
from pathlib import Path

PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "review.md"


class ReviewPromptTests(unittest.TestCase):
    def test_review_prompt_requires_both_reviewers_and_frozen_contract(self) -> None:
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn("swift-reviewer", prompt)
        self.assertIn("spec-conformance-reviewer", prompt)
        self.assertIn("frozen `issue-contract.md`", prompt)
        self.assertIn("Do not expand scope from live GitHub state", prompt)
        self.assertIn("both reviewers", prompt)


class ReviewPromptXmlStructureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")

    def test_old_markdown_headers_absent(self) -> None:
        self.assertNotIn("## Contract", self.prompt)
        self.assertNotIn("## Work", self.prompt)
        self.assertNotIn("## Completion gate", self.prompt)

    def test_xml_opening_tags_present(self) -> None:
        self.assertIn("<role>", self.prompt)
        self.assertIn("<contract>", self.prompt)
        self.assertIn("<work>", self.prompt)
        self.assertIn("<completion_gate>", self.prompt)

    def test_xml_closing_tags_present(self) -> None:
        self.assertIn("</role>", self.prompt)
        self.assertIn("</contract>", self.prompt)
        self.assertIn("</work>", self.prompt)
        self.assertIn("</completion_gate>", self.prompt)

    def test_prompt_starts_with_role_tag(self) -> None:
        self.assertTrue(self.prompt.lstrip().startswith("<role>"))


class ReviewPromptBoundedLoopTests(unittest.TestCase):
    """The remediation loop is capped at one repair+rerun, then COMPLETE/BLOCKED (#286)."""

    def setUp(self) -> None:
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")

    def test_describes_single_repair_and_rerun(self) -> None:
        lower = self.prompt.lower()
        self.assertIn("once", lower)
        self.assertIn("rerun", lower)

    def test_does_not_describe_unbounded_loop(self) -> None:
        lower = self.prompt.lower()
        self.assertNotIn("repeat review/remediation until", lower)

    def test_emits_complete_or_blocked_after_single_rerun(self) -> None:
        self.assertIn("COMPLETE", self.prompt)
        self.assertIn("BLOCKED", self.prompt)


class ReviewPromptEnvelopeAuthorityTests(unittest.TestCase):
    """The controller-injected envelope owns allowed/forbidden actions (#286)."""

    def setUp(self) -> None:
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")

    def test_does_not_restate_forbidden_action_phrases(self) -> None:
        lower = self.prompt.lower()
        self.assertNotIn("workouttrackeruitests bundle", lower)
        self.assertNotIn("ui interaction suite", lower)
        self.assertNotIn("do not push, merge, open a pr, close a pr, or close the issue", lower)

    def test_doc_reads_other_than_frozen_contract_are_conditional(self) -> None:
        self.assertIn("frozen `issue-contract.md`", self.prompt)
        self.assertNotIn(
            "Read `CONTEXT.md`, relevant ADRs, and `AGENTS.md` / `CLAUDE.md` only as needed",
            self.prompt,
        )

    def test_no_mandatory_observations_block(self) -> None:
        self.assertNotIn("<observations>NONE</observations>", self.prompt)
        self.assertNotIn("emit exactly one observations block", self.prompt.lower())


if __name__ == "__main__":
    unittest.main()
