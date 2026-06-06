from __future__ import annotations

import unittest
from pathlib import Path

DIAGNOSE_PATH = Path(__file__).resolve().parents[1] / "prompts" / "diagnose.md"


class DiagnosePromptXmlStructureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.prompt = DIAGNOSE_PATH.read_text(encoding="utf-8")

    def test_old_markdown_headers_absent(self) -> None:
        self.assertNotIn("## Contract", self.prompt)
        self.assertNotIn("## Work", self.prompt)
        self.assertNotIn("## Completion gate", self.prompt)
        self.assertNotIn("## Diagnosis handoff", self.prompt)
        self.assertNotIn("## Diagnosis authority block", self.prompt)

    def test_xml_opening_tags_present(self) -> None:
        self.assertIn("<role>", self.prompt)
        self.assertIn("<contract>", self.prompt)
        self.assertIn("<work>", self.prompt)
        self.assertIn("<diagnosis_handoff>", self.prompt)
        self.assertIn("<diagnosis_authority_instructions>", self.prompt)
        self.assertIn("<completion_gate>", self.prompt)

    def test_xml_closing_tags_present(self) -> None:
        self.assertIn("</role>", self.prompt)
        self.assertIn("</contract>", self.prompt)
        self.assertIn("</work>", self.prompt)
        self.assertIn("</diagnosis_handoff>", self.prompt)
        self.assertIn("</diagnosis_authority_instructions>", self.prompt)
        self.assertIn("</completion_gate>", self.prompt)

    def test_prompt_starts_with_role_tag(self) -> None:
        self.assertTrue(self.prompt.lstrip().startswith("<role>"))

    def test_gh_issue_view_present(self) -> None:
        self.assertIn("gh issue view", self.prompt)

    def test_example_tags_count(self) -> None:
        self.assertEqual(self.prompt.count("<example>"), 2)
        self.assertEqual(self.prompt.count("</example>"), 2)

    def test_diagnosis_authority_blocks_count(self) -> None:
        self.assertEqual(self.prompt.count("<diagnosis-authority>"), 2)

    def test_ui_integration_test_edits_required_present(self) -> None:
        self.assertIn("ui_integration_test_edits_required", self.prompt)


if __name__ == "__main__":
    unittest.main()
