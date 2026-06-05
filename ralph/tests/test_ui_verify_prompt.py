from __future__ import annotations

import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "ui-verify.md"


class UIVerifyPromptTests(unittest.TestCase):
    def test_ui_verify_prompt_excludes_ralph_screenshot_gate(self) -> None:
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertNotIn("ralph/snapshot.sh", prompt)
        self.assertNotIn("UI_SHOT_PATH", prompt)
        self.assertNotIn("UI_REVIEW_PATH", prompt)
        self.assertNotIn("screenshot exists", prompt)

    def test_ui_verify_prompt_excludes_model_visual_review(self) -> None:
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn("Programmatic Visual Regression tests are the visual gate", prompt)
        self.assertNotIn("visual-baseline-reviews", prompt)
        self.assertNotIn("ui-screenshot-reviewer", prompt)
        self.assertNotIn("visual-baseline-diff.swift", prompt)
        self.assertNotIn("baseline-diff review", prompt)


if __name__ == "__main__":
    unittest.main()
