from __future__ import annotations

import unittest

from ralph.orchestrator.contracts import parse_ui_test_authorization
from ralph.orchestrator.diagnosis import (
    DiagnosisAuthorityStatus,
    apply_ui_test_authority,
    parse_diagnosis_authority,
    render_authority_comment,
)

_REQUIRED_BLOCK = (
    "<diagnosis-authority>\n"
    "ui_integration_test_edits_required: true\n"
    "scope: Tests/UI/WorkoutTrackerUITests.swift\n"
    "reason: Only the UI route proves the tap reaches the visible state.\n"
    "</diagnosis-authority>"
)

_NOT_REQUIRED_BLOCK = (
    "<diagnosis-authority>\n"
    "ui_integration_test_edits_required: false\n"
    "scope:\n"
    "reason:\n"
    "</diagnosis-authority>"
)


class ParseDiagnosisAuthorityTests(unittest.TestCase):
    def test_required_block_grants_ui_tests(self) -> None:
        parse = parse_diagnosis_authority(f"findings...\n\n{_REQUIRED_BLOCK}\n")

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.GRANT_UI_TESTS)
        self.assertTrue(parse.is_valid)
        self.assertIsNotNone(parse.authority)
        self.assertTrue(parse.authority.ui_integration_test_edits_required)
        self.assertEqual(parse.authority.scope, ("Tests/UI/WorkoutTrackerUITests.swift",))
        self.assertIn("UI route", parse.authority.reason)

    def test_not_required_block_is_valid_with_no_scope(self) -> None:
        parse = parse_diagnosis_authority(_NOT_REQUIRED_BLOCK)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.NOT_REQUIRED)
        self.assertTrue(parse.is_valid)
        self.assertFalse(parse.authority.ui_integration_test_edits_required)
        self.assertEqual(parse.authority.scope, ())

    def test_missing_block_is_malformed(self) -> None:
        parse = parse_diagnosis_authority("a diagnosis with no authority block")

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertTrue(parse.needs_corrective_pass)
        self.assertIn("no <diagnosis-authority>", parse.error)

    def test_non_boolean_value_is_malformed(self) -> None:
        block = (
            "<diagnosis-authority>\n"
            "ui_integration_test_edits_required: maybe\n"
            "scope:\n"
            "reason:\n"
            "</diagnosis-authority>"
        )

        parse = parse_diagnosis_authority(block)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("true", parse.error)

    def test_required_without_scope_is_malformed(self) -> None:
        block = (
            "<diagnosis-authority>\n"
            "ui_integration_test_edits_required: true\n"
            "scope:\n"
            "reason: needed\n"
            "</diagnosis-authority>"
        )

        parse = parse_diagnosis_authority(block)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("scope", parse.error)

    def test_required_without_reason_is_malformed(self) -> None:
        block = (
            "<diagnosis-authority>\n"
            "ui_integration_test_edits_required: true\n"
            "scope: Tests/UI/WorkoutTrackerUITests.swift\n"
            "reason:\n"
            "</diagnosis-authority>"
        )

        parse = parse_diagnosis_authority(block)

        self.assertEqual(parse.status, DiagnosisAuthorityStatus.MALFORMED)
        self.assertIn("reason", parse.error)

    def test_scope_outside_ui_tests_is_out_of_scope(self) -> None:
        block = (
            "<diagnosis-authority>\n"
            "ui_integration_test_edits_required: true\n"
            "scope: Tests/UI/WorkoutTrackerUITests.swift, project.yml\n"
            "reason: also needs target wiring\n"
            "</diagnosis-authority>"
        )

        parse = parse_diagnosis_authority(block)

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
