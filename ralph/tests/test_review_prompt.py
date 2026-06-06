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


if __name__ == "__main__":
    unittest.main()
