from __future__ import annotations

import json
import unittest

from ralph.orchestrator.contracts import parse_ui_test_authorization
from ralph.orchestrator.diagnosis import (
    DiagnosisAuthorityStatus,
    apply_ui_test_authority,
    parse_diagnosis_authority,
    render_authority_comment,
)

# Every well-formed artifact carries the handoff fields the parser now requires.
_HANDOFF = {
    "root_cause": "Tap never reaches the visible writable row.",
    "fix_plan": "Route the gesture through the real control.",
    "test_seam": "Tests/UI integration proves the visible state.",
}


def _block(payload: dict) -> str:
    return f"<diagnosis-result>\n{json.dumps(payload, indent=2)}\n</diagnosis-result>"


_REQUIRED_PAYLOAD = {
    **_HANDOFF,
    "ui_integration_test_edits_required": True,
    "scope": ["Tests/UI/WorkoutTrackerUITests.swift"],
    "reason": "Only the UI route proves the tap reaches the visible state.",
}
_REQUIRED_BLOCK = _block(_REQUIRED_PAYLOAD)

_NOT_REQUIRED_PAYLOAD = {**_HANDOFF, "ui_integration_test_edits_required": False}
_NOT_REQUIRED_BLOCK = _block(_NOT_REQUIRED_PAYLOAD)


class ParseDiagnosisAuthorityTests(unittest.TestCase):
    def test_required_block_grants_ui_tests(self) -> None:
        parse = parse_diagnosis_authority(f"findings...\n\n{_REQUIRED_BLOCK}\n")

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.GRANT_UI_TESTS)
        self.assertTrue(parse.is_valid)
        self.assertIsNotNone(parse.authority)
        self.assertTrue(parse.authority.ui_integration_test_edits_required)
        self.assertEqual(parse.authority.scope, ("Tests/UI/WorkoutTrackerUITests.swift",))
        self.assertIn("UI route", parse.authority.reason)

    def test_artifact_captures_handoff_fields(self) -> None:
        parse = parse_diagnosis_authority(_NOT_REQUIRED_BLOCK)

        self.assertIn("visible writable row", parse.authority.root_cause)
        self.assertIn("real control", parse.authority.fix_plan)
        self.assertIn("Tests/UI integration", parse.authority.test_seam)

    def test_not_required_block_is_valid_with_no_scope(self) -> None:
        parse = parse_diagnosis_authority(_NOT_REQUIRED_BLOCK)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.NOT_REQUIRED)
        self.assertTrue(parse.is_valid)
        self.assertFalse(parse.authority.ui_integration_test_edits_required)
        self.assertEqual(parse.authority.scope, ())

    def test_missing_block_is_malformed(self) -> None:
        parse = parse_diagnosis_authority("a diagnosis with no result artifact")

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertTrue(parse.needs_corrective_pass)
        self.assertIn("no <diagnosis-result>", parse.error)

    def test_non_json_body_is_malformed(self) -> None:
        block = (
            "<diagnosis-result>\n"
            "root_cause: not json at all\n"
            "fix_plan: nope\n"
            "</diagnosis-result>"
        )

        parse = parse_diagnosis_authority(block)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertTrue(parse.needs_corrective_pass)
        self.assertIn("not valid JSON", parse.error)

    def test_non_object_json_is_malformed(self) -> None:
        block = "<diagnosis-result>\n[1, 2, 3]\n</diagnosis-result>"

        parse = parse_diagnosis_authority(block)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("JSON object", parse.error)

    def test_missing_handoff_field_is_malformed(self) -> None:
        payload = {
            "fix_plan": "route the gesture",
            "test_seam": "Tests/UI integration",
            "ui_integration_test_edits_required": False,
        }

        parse = parse_diagnosis_authority(_block(payload))

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("root_cause", parse.error)

    def test_non_boolean_value_is_malformed(self) -> None:
        payload = {**_HANDOFF, "ui_integration_test_edits_required": "maybe"}

        parse = parse_diagnosis_authority(_block(payload))

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("boolean", parse.error)

    def test_required_without_scope_is_malformed(self) -> None:
        payload = {
            **_HANDOFF,
            "ui_integration_test_edits_required": True,
            "scope": [],
            "reason": "needed",
        }

        parse = parse_diagnosis_authority(_block(payload))

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("scope", parse.error)

    def test_required_without_reason_is_malformed(self) -> None:
        payload = {
            **_HANDOFF,
            "ui_integration_test_edits_required": True,
            "scope": ["Tests/UI/WorkoutTrackerUITests.swift"],
            "reason": "",
        }

        parse = parse_diagnosis_authority(_block(payload))

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("reason", parse.error)

    def test_scope_outside_ui_tests_is_out_of_scope(self) -> None:
        payload = {
            **_HANDOFF,
            "ui_integration_test_edits_required": True,
            "scope": ["Tests/UI/WorkoutTrackerUITests.swift", "project.yml"],
            "reason": "also needs target wiring",
        }

        parse = parse_diagnosis_authority(_block(payload))

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.OUT_OF_SCOPE)
        self.assertTrue(parse.needs_human_escalation)
        self.assertFalse(parse.is_valid)
        self.assertEqual(parse.out_of_scope_paths, ("project.yml",))

    def test_first_block_wins(self) -> None:
        parse = parse_diagnosis_authority(f"{_NOT_REQUIRED_BLOCK}\n{_REQUIRED_BLOCK}")

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.NOT_REQUIRED)


class ApplyUiTestAuthorityTests(unittest.TestCase):
    def test_appends_new_section_when_absent(self) -> None:
        body = "Bug: tapping log does nothing.\n"

        updated = apply_ui_test_authority(
            body, scope=["Tests/UI/WorkoutTrackerUITests.swift"], reason="real-control route"
        )

        self.assertTrue(parse_ui_test_authorization(updated))
        self.assertIn("## Test authority", updated)
        self.assertIn("Diagnosis scope: Tests/UI/WorkoutTrackerUITests.swift", updated)
        self.assertIn("Diagnosis reason: real-control route", updated)
        self.assertNotEqual(updated, body)
        # Original body content preserved.
        self.assertIn("Bug: tapping log does nothing.", updated)

    def test_reuses_existing_section(self) -> None:
        body = "Intro\n\n## Test authority\n\nSome prior note.\n\n## Other\n\nkeep me\n"

        updated = apply_ui_test_authority(body, scope=["Tests/UI/Foo.swift"], reason="r")

        self.assertTrue(parse_ui_test_authorization(updated))
        # Only one Test authority heading; marker landed inside that section.
        self.assertEqual(updated.count("## Test authority"), 1)
        before_other = updated.split("## Other", 1)[0]
        self.assertIn("UI integration test edits: authorized", before_other)
        self.assertIn("Some prior note.", before_other)
        self.assertIn("## Other\n\nkeep me", updated)

    def test_idempotent_when_already_authorized(self) -> None:
        body = "x\n\n## Test authority\n\nUI integration test edits: authorized\n"

        updated = apply_ui_test_authority(body, scope=["Tests/UI/Foo.swift"], reason="r")

        self.assertEqual(updated, body)

    def test_does_not_mutate_input(self) -> None:
        body = "frozen\n"
        original = str(body)

        apply_ui_test_authority(body, scope=["Tests/UI/Foo.swift"], reason="r")

        self.assertEqual(body, original)


class RenderAuthorityCommentTests(unittest.TestCase):
    def test_records_scope_and_reason_as_audit_event(self) -> None:
        comment = render_authority_comment(
            42, ["Tests/UI/WorkoutTrackerUITests.swift"], "lower layers cannot prove it"
        )

        self.assertIn("#42", comment)
        self.assertIn("Tests/UI/WorkoutTrackerUITests.swift", comment)
        self.assertIn("lower layers cannot prove it", comment)
        self.assertIn("audit", comment.lower())


if __name__ == "__main__":
    unittest.main()
