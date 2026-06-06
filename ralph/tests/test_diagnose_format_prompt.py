from __future__ import annotations

import unittest
from pathlib import Path

PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "diagnose-format.md"


class DiagnoseFormatPromptXmlStructureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")

    def test_old_markdown_headers_absent(self) -> None:
        self.assertNotIn("## Work", self.prompt)
        self.assertNotIn("## Completion gate", self.prompt)

    def test_xml_opening_tags_present(self) -> None:
        self.assertIn("<role>", self.prompt)
        self.assertIn("<work>", self.prompt)
        self.assertIn("<completion_gate>", self.prompt)

    def test_xml_closing_tags_present(self) -> None:
        self.assertIn("</role>", self.prompt)
        self.assertIn("</work>", self.prompt)
        self.assertIn("</completion_gate>", self.prompt)

    def test_prompt_starts_with_role_tag(self) -> None:
        self.assertTrue(self.prompt.lstrip().startswith("<role>"))


if __name__ == "__main__":
    unittest.main()
