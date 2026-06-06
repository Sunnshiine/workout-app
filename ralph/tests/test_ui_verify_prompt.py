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


class UIVerifyPromptSmokeVocabularyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")

    def test_ui_verify_uses_class_level_selectors(self) -> None:
        # Must instruct agents to use class-level selectors, not the full bundle
        self.assertIn("-only-testing:WorkoutTrackerUITests/", self.prompt)

    def test_ui_verify_does_not_ask_for_full_bundle(self) -> None:
        # Must NOT ask for the bare full-bundle selector
        # Allow occurrences only when followed by a "/" (class-level selector)
        import re

        matches = re.findall(r"-only-testing:WorkoutTrackerUITests(\S*)", self.prompt)
        for suffix in matches:
            self.assertTrue(
                suffix.startswith("/"),
                "Found full -only-testing:WorkoutTrackerUITests bundle selector without class path",
            )

    def test_ui_verify_preserves_three_test_categories(self) -> None:
        self.assertIn("Visual Regression", self.prompt)
        self.assertIn("UI Integration Smoke", self.prompt)
        self.assertIn("UI Interaction Suite", self.prompt)


if __name__ == "__main__":
    unittest.main()
