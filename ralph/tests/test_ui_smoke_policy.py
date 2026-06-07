from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FULL_TARGET_SELECTOR = re.compile(r"-only-testing:WorkoutTrackerUITests(?:\s|$)")


class RalphUISmokePolicyTests(unittest.TestCase):
    def test_readme_documents_smoke_and_manual_interaction_suite(self) -> None:
        readme = (ROOT / "ralph" / "README.md").read_text(encoding="utf-8")

        self.assertIn("UI Integration Smoke", readme)
        self.assertIn("WorkoutTrackerUITests/WorkoutTrackerUISmokeTests", readme)
        self.assertIn("WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests", readme)
        self.assertIn("UI Interaction Suite", readme)
        self.assertIn("manual or non-Ralph", readme)
        self.assertNotIn("- Xcode UI integration tests for `WorkoutTrackerUITests`", readme)
        self.assertIsNone(FULL_TARGET_SELECTOR.search(readme))


if __name__ == "__main__":
    unittest.main()
