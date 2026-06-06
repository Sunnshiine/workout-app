from __future__ import annotations

import unittest
from dataclasses import FrozenInstanceError

from ralph.orchestrator.contracts import (
    UI_TEST_AUTHORIZATION_LINE,
    IssueContract,
    capture_issue_contract,
    parse_blocked_by,
    parse_prd_number,
    parse_ui_test_authorization,
)
from ralph.orchestrator.github import FakeGitHubClient


def _client_with_body(number: int, body: str, **extra) -> FakeGitHubClient:
    issue = {"number": number, "title": f"Issue {number}", "body": body}
    issue.update(extra)
    return FakeGitHubClient(issues={number: issue})


class CaptureContractTests(unittest.TestCase):
    def test_one_off_issue_has_no_prd(self) -> None:
        client = _client_with_body(42, "Plain body, no directives.")
        contract = capture_issue_contract(client, 42)
        self.assertIsInstance(contract, IssueContract)
        self.assertEqual(contract.number, 42)
        self.assertIsNone(contract.prd_number)
        self.assertFalse(contract.ui_test_edits_authorized)

    def test_prd_directive_in_body_is_captured(self) -> None:
        client = _client_with_body(50, "Some intro\nPRD: #12\nmore text")
        contract = capture_issue_contract(client, 50)
        self.assertEqual(contract.prd_number, 12)

    def test_labels_normalized_to_frozenset(self) -> None:
        client = _client_with_body(
            9,
            "body",
            labels=[{"name": "ready-for-agent"}, {"name": "bug"}],
        )
        contract = capture_issue_contract(client, 9)
        self.assertEqual(contract.labels, frozenset({"ready-for-agent", "bug"}))

    def test_comments_kept_for_context_only(self) -> None:
        client = _client_with_body(
            3,
            "body",
            comments=[{"author": {"login": "kevin"}, "body": "PRD: #99"}],
        )
        contract = capture_issue_contract(client, 3)
        self.assertEqual(len(contract.comments_for_context), 1)
        self.assertEqual(contract.comments_for_context[0].author, "kevin")
        # A PRD directive that lives only in a comment must NOT grant membership.
        self.assertIsNone(contract.prd_number)

    def test_contract_is_immutable(self) -> None:
        contract = capture_issue_contract(_client_with_body(1, "b"), 1)
        with self.assertRaises(FrozenInstanceError):
            contract.prd_number = 5  # type: ignore[misc]


class PrdParsingTests(unittest.TestCase):
    def test_exact_directive(self) -> None:
        self.assertEqual(parse_prd_number("PRD: #7"), 7)

    def test_directive_with_surrounding_lines(self) -> None:
        self.assertEqual(parse_prd_number("intro\n  PRD: #15  \noutro"), 15)

    def test_inline_mention_does_not_count(self) -> None:
        self.assertIsNone(parse_prd_number("This relates to PRD: #15 in passing."))

    def test_missing_directive(self) -> None:
        self.assertIsNone(parse_prd_number("no directive here"))

    def test_first_directive_wins(self) -> None:
        self.assertEqual(parse_prd_number("PRD: #1\nPRD: #2"), 1)


class BlockedByParsingTests(unittest.TestCase):
    def test_single_dependency_in_section(self) -> None:
        body = "## Blocked by\n\n- #222\n"
        self.assertEqual(parse_blocked_by(body), (222,))

    def test_multiple_dependencies_preserve_order(self) -> None:
        body = "## Blocked by\n\n- #222\n- #223\n"
        self.assertEqual(parse_blocked_by(body), (222, 223))

    def test_duplicates_are_removed(self) -> None:
        body = "## Blocked by\n\n- #222\n- #222\n"
        self.assertEqual(parse_blocked_by(body), (222,))

    def test_section_ends_at_next_heading(self) -> None:
        body = "## Blocked by\n\n- #222\n\n## Notes\n\n- #999\n"
        self.assertEqual(parse_blocked_by(body), (222,))

    def test_out_of_section_mention_is_ignored(self) -> None:
        body = "Refs #222 in the summary.\n\n## Details\n\nNo deps here.\n"
        self.assertEqual(parse_blocked_by(body), ())

    def test_no_section_returns_empty(self) -> None:
        self.assertEqual(parse_blocked_by("Just a body with #5 mentioned."), ())

    def test_section_captured_in_contract(self) -> None:
        client = _client_with_body(9, "## Blocked by\n\n- #222\n")
        contract = capture_issue_contract(client, 9)
        self.assertEqual(contract.blocked_by, (222,))


class UiTestAuthorizationTests(unittest.TestCase):
    def test_exact_line_authorizes(self) -> None:
        body = f"intro\n{UI_TEST_AUTHORIZATION_LINE}\noutro"
        self.assertTrue(parse_ui_test_authorization(body))

    def test_line_with_whitespace_padding_authorizes(self) -> None:
        body = f"  {UI_TEST_AUTHORIZATION_LINE}  "
        self.assertTrue(parse_ui_test_authorization(body))

    def test_fuzzy_mention_does_not_authorize(self) -> None:
        self.assertFalse(
            parse_ui_test_authorization("UI integration test edits: authorized for the win")
        )

    def test_unrelated_prose_does_not_authorize(self) -> None:
        self.assertFalse(parse_ui_test_authorization("UI integration tests are fine"))

    def test_authorization_from_comment_is_ignored(self) -> None:
        # The marker only counts in the body snapshot, never in a comment.
        client = _client_with_body(
            8,
            "body without marker",
            comments=[{"author": {"login": "kevin"}, "body": UI_TEST_AUTHORIZATION_LINE}],
        )
        contract = capture_issue_contract(client, 8)
        self.assertFalse(contract.ui_test_edits_authorized)

    def test_authorization_in_body_snapshot(self) -> None:
        client = _client_with_body(8, f"setup\n{UI_TEST_AUTHORIZATION_LINE}")
        contract = capture_issue_contract(client, 8)
        self.assertTrue(contract.ui_test_edits_authorized)


if __name__ == "__main__":
    unittest.main()
