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

    def test_xml_opening_tags_present(self) -> None:
        self.assertIn("<role>", self.prompt)
        self.assertIn("<contract>", self.prompt)
        self.assertIn("<work>", self.prompt)
        self.assertIn("<diagnosis_artifact_instructions>", self.prompt)
        self.assertIn("<completion_gate>", self.prompt)

    def test_xml_closing_tags_present(self) -> None:
        self.assertIn("</role>", self.prompt)
        self.assertIn("</contract>", self.prompt)
        self.assertIn("</work>", self.prompt)
        self.assertIn("</diagnosis_artifact_instructions>", self.prompt)
        self.assertIn("</completion_gate>", self.prompt)

    def test_prompt_starts_with_role_tag(self) -> None:
        self.assertTrue(self.prompt.lstrip().startswith("<role>"))

    def test_gh_issue_view_present(self) -> None:
        self.assertIn("gh issue view", self.prompt)

    def test_example_tags_count(self) -> None:
        self.assertEqual(self.prompt.count("<example>"), 2)
        self.assertEqual(self.prompt.count("</example>"), 2)

    def test_emits_structured_diagnosis_result_artifact(self) -> None:
        # Two fenced examples (UI-required / not-required); the legacy block is gone.
        self.assertEqual(self.prompt.count("</diagnosis-result>"), 2)
        self.assertNotIn("<diagnosis-authority>", self.prompt)

    def test_artifact_handoff_fields_present(self) -> None:
        for field in ("root_cause", "fix_plan", "test_seam"):
            self.assertIn(field, self.prompt)

    def test_ui_integration_test_edits_required_present(self) -> None:
        self.assertIn("ui_integration_test_edits_required", self.prompt)

    def test_no_envelope_action_list_restated(self) -> None:
        # The controller-injected envelope owns allowed/forbidden actions; the body
        # must not restate the forbidden-commit/push rule in prose.
        self.assertNotIn("You MUST NOT commit", self.prompt)
        self.assertNotIn("rewrite `main`", self.prompt)

    def test_doc_reads_are_conditional(self) -> None:
        # CONTEXT/ADR/TESTING reads are scoped to the bug, not an unconditional checklist.
        self.assertIn("only as the bug requires", self.prompt)


if __name__ == "__main__":
    unittest.main()
