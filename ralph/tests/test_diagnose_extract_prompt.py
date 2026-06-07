from __future__ import annotations

import unittest
from pathlib import Path

from ralph.orchestrator.loop import PHASE_DIAGNOSE_EXTRACT, _forbidden_actions_for_phase

_PROMPT = (
    Path(__file__).resolve().parents[2] / "ralph" / "prompts" / "diagnose-extract.md"
).read_text(encoding="utf-8")


class DiagnoseExtractPromptTests(unittest.TestCase):
    def test_prompt_file_exists_and_starts_with_role(self) -> None:
        self.assertTrue(_PROMPT.strip())
        self.assertTrue(_PROMPT.lstrip().startswith("<role>"))

    def test_requires_single_json_diagnosis_result_artifact(self) -> None:
        # Two worked examples each carry one tag-only line pair; the rest of
        # the prose only names the tag inline without wrapping content in it.
        lines = [line.strip() for line in _PROMPT.splitlines()]
        self.assertEqual(lines.count("<diagnosis-result>"), 2)
        self.assertEqual(lines.count("</diagnosis-result>"), 2)
        self.assertIn("EXACTLY ONE", _PROMPT.upper())
        self.assertIn("JSON", _PROMPT)
        self.assertIn("json.loads", _PROMPT)

    def test_names_schema_fields(self) -> None:
        for field in (
            "root_cause",
            "fix_plan",
            "test_seam",
            "ui_integration_test_edits_required",
            "scope",
            "reason",
            "blocked_reason",
        ):
            with self.subTest(field=field):
                self.assertIn(field, _PROMPT)

    def test_carries_both_worked_examples(self) -> None:
        self.assertIn('"ui_integration_test_edits_required": true', _PROMPT)
        self.assertIn('"ui_integration_test_edits_required": false', _PROMPT)
        self.assertIn("Tests/UI/WorkoutTrackerUITests.swift", _PROMPT)

    def test_forbids_editing_committing_and_re_diagnosing(self) -> None:
        forbidden = " ".join(_forbidden_actions_for_phase(PHASE_DIAGNOSE_EXTRACT))

        self.assertIn("edit", forbidden.lower())
        self.assertIn("commit", forbidden.lower())
        self.assertIn("diagnos", forbidden.lower())
        self.assertGreater(len(_forbidden_actions_for_phase(PHASE_DIAGNOSE_EXTRACT)), 0)


if __name__ == "__main__":
    unittest.main()
