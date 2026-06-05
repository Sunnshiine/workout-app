from __future__ import annotations

import json
import unittest

from ralph.orchestrator.github import (
    FakeGitHubClient,
    GhCliClient,
    GitHubClient,
    GitHubClientError,
)


class FakeGitHubClientTests(unittest.TestCase):
    def test_view_issue_returns_a_copy(self) -> None:
        fixture = {7: {"number": 7, "title": "T", "body": "B"}}
        client = FakeGitHubClient(issues=fixture)
        result = client.view_issue(7)
        self.assertEqual(result["title"], "T")
        result["title"] = "mutated"
        # Mutating the returned dict must not corrupt the stored fixture.
        self.assertEqual(client.view_issue(7)["title"], "T")

    def test_view_missing_issue_raises(self) -> None:
        with self.assertRaises(GitHubClientError):
            FakeGitHubClient().view_issue(404)

    def test_list_open_issues_filters_by_label(self) -> None:
        client = FakeGitHubClient(
            issues={
                1: {"number": 1, "labels": [{"name": "ready-for-agent"}]},
                2: {"number": 2, "labels": [{"name": "wontfix"}]},
            }
        )
        labelled = client.list_open_issues(label="ready-for-agent")
        self.assertEqual([i["number"] for i in labelled], [1])
        self.assertEqual(len(client.list_open_issues()), 2)

    def test_list_open_prs_filters_by_head(self) -> None:
        client = FakeGitHubClient(
            open_prs=[
                {"number": 11, "headRefName": "ralph/issue-9"},
                {"number": 12, "headRefName": "ralph/prd-3"},
            ]
        )
        self.assertEqual(
            [p["number"] for p in client.list_open_prs(head="ralph/prd-3")],
            [12],
        )
        self.assertEqual(len(client.list_open_prs()), 2)

    def test_satisfies_protocol(self) -> None:
        self.assertIsInstance(FakeGitHubClient(), GitHubClient)

    def test_create_pr_records_and_assigns_number(self) -> None:
        client = FakeGitHubClient(next_pr_number=500)
        number = client.create_pr(
            draft=True, base="main", head="ralph/issue-7", title="t", body="b"
        )
        self.assertEqual(number, 500)
        self.assertTrue(client.pr_is_draft(number))
        found = client.find_pr_by_head_branch("ralph/issue-7")
        self.assertEqual(found["number"], 500)
        self.assertEqual(client.calls[0][0], "create_pr")

    def test_find_pr_by_head_branch_returns_none_when_absent(self) -> None:
        self.assertIsNone(FakeGitHubClient().find_pr_by_head_branch("ralph/issue-1"))

    def test_mark_pr_ready_clears_draft(self) -> None:
        client = FakeGitHubClient()
        number = client.create_pr(
            draft=True, base="main", head="ralph/issue-1", title="t", body="b"
        )
        client.mark_pr_ready(number)
        self.assertFalse(client.pr_is_draft(number))

    def test_issue_label_add_and_remove_are_idempotent(self) -> None:
        client = FakeGitHubClient(issues={3: {"number": 3, "labels": [{"name": "keep"}]}})
        client.add_issue_labels(3, ["agent-implemented"])
        client.add_issue_labels(3, ["agent-implemented"])  # de-duplicated
        client.remove_issue_labels(3, ["keep"])
        self.assertEqual(client.issue_labels(3), {"agent-implemented"})

    def test_comment_issue_appends_comment(self) -> None:
        client = FakeGitHubClient(issues={3: {"number": 3}})
        client.comment_issue(3, "hello")
        self.assertEqual(client.view_issue(3)["comments"][0]["body"], "hello")


class GhCliClientTests(unittest.TestCase):
    """Exercise GhCliClient through an injected runner; never spawns real gh."""

    def test_view_issue_builds_argv_and_parses_json(self) -> None:
        recorded: list[list[str]] = []

        def runner(argv):
            recorded.append(list(argv))
            return json.dumps({"number": 5, "title": "X", "body": "y"})

        client = GhCliClient(repo="owner/name", runner=runner)
        issue = client.view_issue(5)

        self.assertEqual(issue["number"], 5)
        argv = recorded[0]
        self.assertEqual(argv[:4], ["gh", "issue", "view", "5"])
        self.assertIn("--repo", argv)
        self.assertIn("owner/name", argv)
        self.assertIn("--json", argv)

    def test_list_open_prs_passes_head_filter(self) -> None:
        recorded: list[list[str]] = []

        def runner(argv):
            recorded.append(list(argv))
            return json.dumps([{"number": 3, "headRefName": "ralph/prd-2"}])

        client = GhCliClient(runner=runner)
        prs = client.list_open_prs(head="ralph/prd-2")

        self.assertEqual(prs[0]["number"], 3)
        argv = recorded[0]
        self.assertIn("--head", argv)
        self.assertIn("ralph/prd-2", argv)
        self.assertIn("--state", argv)
        self.assertIn("open", argv)

    def test_non_json_output_raises_client_error(self) -> None:
        client = GhCliClient(runner=lambda _argv: "not json")
        with self.assertRaises(GitHubClientError):
            client.view_issue(1)

    def test_issue_view_non_object_raises(self) -> None:
        client = GhCliClient(runner=lambda _argv: json.dumps([1, 2, 3]))
        with self.assertRaises(GitHubClientError):
            client.view_issue(1)

    def test_create_pr_builds_draft_argv_and_parses_number(self) -> None:
        recorded: list[list[str]] = []

        def runner(argv):
            recorded.append(list(argv))
            return "https://github.com/owner/name/pull/321\n"

        client = GhCliClient(repo="owner/name", runner=runner)
        number = client.create_pr(
            draft=True, base="main", head="ralph/issue-7", title="t", body="b"
        )

        self.assertEqual(number, 321)
        argv = recorded[0]
        self.assertEqual(argv[:3], ["gh", "pr", "create"])
        self.assertIn("--draft", argv)
        self.assertIn("ralph/issue-7", argv)

    def test_add_issue_labels_builds_edit_argv(self) -> None:
        recorded: list[list[str]] = []

        def runner(argv):
            recorded.append(list(argv))
            return ""

        client = GhCliClient(runner=runner)
        client.add_issue_labels(7, ["agent-implemented"])

        argv = recorded[0]
        self.assertEqual(argv[:3], ["gh", "issue", "edit"])
        self.assertIn("--add-label", argv)
        self.assertIn("agent-implemented", argv)

    def test_create_pr_unparseable_url_raises(self) -> None:
        client = GhCliClient(runner=lambda _argv: "not-a-url")
        with self.assertRaises(GitHubClientError):
            client.create_pr(draft=False, base="main", head="h", title="t", body="b")


if __name__ == "__main__":
    unittest.main()
