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


if __name__ == "__main__":
    unittest.main()
