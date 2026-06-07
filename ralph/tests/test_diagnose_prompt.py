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
        self.assertIn("<completion_gate>", self.prompt)

    def test_xml_closing_tags_present(self) -> None:
        self.assertIn("</role>", self.prompt)
        self.assertIn("</contract>", self.prompt)
        self.assertIn("</work>", self.prompt)
        self.assertIn("</completion_gate>", self.prompt)

    def test_prompt_starts_with_role_tag(self) -> None:
        self.assertTrue(self.prompt.lstrip().startswith("<role>"))

    def test_gh_issue_view_present(self) -> None:
        self.assertIn("gh issue view", self.prompt)

    def test_no_diagnosis_result_artifact_format(self) -> None:
        # The artifact format now lives solely in diagnose-extract.md.
        self.assertNotIn("<diagnosis-result>", self.prompt)
        self.assertNotIn("<example>", self.prompt)
        self.assertNotIn("ui_integration_test_edits_required", self.prompt)

    def test_retains_diagnose_skill_mandate(self) -> None:
        self.assertIn("Must invoke the", self.prompt)
        self.assertIn("diagnose", self.prompt)
        self.assertIn("skill", self.prompt)

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
