"""GitHub access seam.

Every GitHub read in the Python runner goes through a ``GitHubClient`` so tests
can substitute an in-memory ``FakeGitHubClient`` and never touch the real ``gh``
CLI or the network. This slice exposes only the reads the issue-contract and
target-resolution layers need; later issues extend the protocol.
"""

from __future__ import annotations

import json
import subprocess
from collections.abc import Callable, Iterable, Mapping, Sequence
from typing import Protocol, runtime_checkable

# Fields requested from ``gh issue view`` for the contract snapshot.
_ISSUE_VIEW_FIELDS = "number,title,body,labels,comments,state"
# Fields requested from ``gh pr list`` for branch-reuse lookup/readiness.
_PR_LIST_FIELDS = "number,headRefName,state,isDraft"


@runtime_checkable
class GitHubClient(Protocol):
    """GitHub seam used by the orchestrator.

    Implementations return plain ``dict``/``list`` JSON shapes (as ``gh``
    produces). Callers validate and normalize those shapes; the client only
    fetches them. Write methods mutate GitHub state (labels, PRs, comments) and
    are the only sanctioned way the orchestrator touches the repo.
    """

    def view_issue(self, number: int) -> dict:
        """Return the issue JSON for ``number`` (number, title, body, labels, comments)."""

    def list_open_issues(self, *, label: str | None = None) -> list[dict]:
        """Return open issues, optionally filtered by ``label``."""

    def list_open_prs(self, *, head: str | None = None) -> list[dict]:
        """Return open PRs, optionally filtered by head branch ``head``."""

    def create_pr(self, *, draft: bool, base: str, head: str, title: str, body: str) -> int:
        """Create a PR from ``head`` into ``base`` and return its number."""

    def find_pr_by_head_branch(self, head: str) -> dict | None:
        """Return the open PR whose head is ``head``, or None if none exists."""

    def mark_pr_ready(self, number: int) -> None:
        """Take PR ``number`` out of draft (mark ready for review)."""

    def add_pr_labels(self, number: int, labels: Sequence[str]) -> None:
        """Add ``labels`` to PR ``number``."""

    def add_issue_labels(self, number: int, labels: Sequence[str]) -> None:
        """Add ``labels`` to issue ``number``."""

    def remove_issue_labels(self, number: int, labels: Sequence[str]) -> None:
        """Remove ``labels`` from issue ``number``."""

    def edit_issue_labels(
        self,
        number: int,
        *,
        add: Sequence[str] = (),
        remove: Sequence[str] = (),
    ) -> None:
        """Apply one issue-label edit containing additions and removals."""

    def comment_issue(self, number: int, body: str) -> None:
        """Post a comment with ``body`` on issue ``number``."""

    def edit_issue_body(self, number: int, body: str) -> None:
        """Replace the body of issue ``number`` with ``body``."""


# A runner is any callable that takes an argv list and returns captured stdout.
# Real use wraps ``subprocess.run``; tests inject a recording fake.
GhRunner = Callable[[Sequence[str]], str]


def _default_gh_runner(argv: Sequence[str]) -> str:
    """Run ``gh`` with ``argv`` and return stdout, raising on non-zero exit."""

    completed = subprocess.run(  # noqa: S603 - argv is fully controlled, never shell.
        list(argv),
        capture_output=True,
        text=True,
        check=True,
    )
    return completed.stdout


class GhCliClient:
    """``GitHubClient`` backed by the ``gh`` CLI.

    All access flows through an injectable ``runner`` so the subprocess seam can
    be faked in tests; production uses the default ``gh`` runner.
    """

    def __init__(self, *, repo: str | None = None, runner: GhRunner | None = None) -> None:
        self._repo = repo
        self._runner = runner or _default_gh_runner

    def _repo_args(self) -> list[str]:
        return ["--repo", self._repo] if self._repo else []

    def _run_json(self, argv: Sequence[str]) -> object:
        raw = self._runner(list(argv))
        try:
            return json.loads(raw)
        except (json.JSONDecodeError, TypeError) as exc:
            joined = " ".join(argv)
            raise GitHubClientError(f"gh returned non-JSON output for: {joined}") from exc

    def view_issue(self, number: int) -> dict:
        argv = [
            "gh",
            "issue",
            "view",
            str(number),
            *self._repo_args(),
            "--json",
            _ISSUE_VIEW_FIELDS,
        ]
        payload = self._run_json(argv)
        if not isinstance(payload, Mapping):
            raise GitHubClientError(f"expected an object from gh issue view {number}")
        return dict(payload)

    def list_open_issues(self, *, label: str | None = None) -> list[dict]:
        argv = [
            "gh",
            "issue",
            "list",
            "--state",
            "open",
            *self._repo_args(),
            "--json",
            "number,title,labels",
        ]
        if label:
            argv += ["--label", label]
        return _as_dict_list(self._run_json(argv))

    def list_open_prs(self, *, head: str | None = None) -> list[dict]:
        argv = [
            "gh",
            "pr",
            "list",
            "--state",
            "open",
            *self._repo_args(),
            "--json",
            _PR_LIST_FIELDS,
        ]
        if head:
            argv += ["--head", head]
        return _as_dict_list(self._run_json(argv))

    def create_pr(self, *, draft: bool, base: str, head: str, title: str, body: str) -> int:
        argv = [
            "gh",
            "pr",
            "create",
            *self._repo_args(),
            "--base",
            base,
            "--head",
            head,
            "--title",
            title,
            "--body",
            body,
        ]
        if draft:
            argv.append("--draft")
        # ``gh pr create`` prints the new PR URL; the number is its last path segment.
        url = self._runner(argv).strip()
        return _pr_number_from_url(url)

    def find_pr_by_head_branch(self, head: str) -> dict | None:
        prs = self.list_open_prs(head=head)
        for pr in prs:
            if pr.get("headRefName") == head:
                return pr
        return None

    def mark_pr_ready(self, number: int) -> None:
        self._runner(["gh", "pr", "ready", str(number), *self._repo_args()])

    def add_pr_labels(self, number: int, labels: Sequence[str]) -> None:
        self._edit_labels("pr", number, add=labels)

    def add_issue_labels(self, number: int, labels: Sequence[str]) -> None:
        self.edit_issue_labels(number, add=labels)

    def remove_issue_labels(self, number: int, labels: Sequence[str]) -> None:
        self.edit_issue_labels(number, remove=labels)

    def edit_issue_labels(
        self,
        number: int,
        *,
        add: Sequence[str] = (),
        remove: Sequence[str] = (),
    ) -> None:
        self._edit_labels("issue", number, add=add, remove=remove)

    def comment_issue(self, number: int, body: str) -> None:
        self._runner(
            [
                "gh",
                "issue",
                "comment",
                str(number),
                *self._repo_args(),
                "--body",
                body,
            ]
        )

    def edit_issue_body(self, number: int, body: str) -> None:
        self._runner(
            [
                "gh",
                "issue",
                "edit",
                str(number),
                *self._repo_args(),
                "--body",
                body,
            ]
        )

    def _edit_labels(
        self,
        kind: str,
        number: int,
        *,
        add: Sequence[str] = (),
        remove: Sequence[str] = (),
    ) -> None:
        if not add and not remove:
            return
        argv = [
            "gh",
            kind,
            "edit",
            str(number),
            *self._repo_args(),
        ]
        for label in add:
            argv += ["--add-label", label]
        for label in remove:
            argv += ["--remove-label", label]
        self._runner(argv)


def _pr_number_from_url(url: str) -> int:
    tail = url.rstrip("/").rsplit("/", 1)[-1]
    if not tail.isdigit():
        raise GitHubClientError(f"could not parse a PR number from gh output: {url!r}")
    return int(tail)


class FakeGitHubClient:
    """In-memory ``GitHubClient`` for tests; never touches network or ``gh``.

    Built from fixture dicts keyed by issue number plus a list of open-PR dicts.
    Write methods mutate the in-memory state and append to ``calls`` so tests can
    assert on the exact sequence of GitHub mutations. PR numbers are assigned
    monotonically from ``_next_pr_number``.
    """

    def __init__(
        self,
        *,
        issues: Mapping[int, Mapping] | None = None,
        open_prs: Iterable[Mapping] | None = None,
        next_pr_number: int = 1000,
    ) -> None:
        self._issues: dict[int, dict] = {int(n): dict(v) for n, v in (issues or {}).items()}
        self._open_prs: list[dict] = [dict(p) for p in (open_prs or [])]
        self._next_pr_number = int(next_pr_number)
        self.calls: list[tuple] = []

    def view_issue(self, number: int) -> dict:
        try:
            return dict(self._issues[int(number)])
        except KeyError as exc:
            raise GitHubClientError(f"no fixture issue #{number}") from exc

    def list_open_issues(self, *, label: str | None = None) -> list[dict]:
        issues = [dict(v) for v in self._issues.values() if v.get("state", "OPEN") == "OPEN"]
        if label is None:
            return issues
        return [i for i in issues if label in _label_names(i.get("labels"))]

    def list_open_prs(self, *, head: str | None = None) -> list[dict]:
        prs = [dict(p) for p in self._open_prs]
        if head is None:
            return prs
        return [p for p in prs if p.get("headRefName") == head]

    def create_pr(self, *, draft: bool, base: str, head: str, title: str, body: str) -> int:
        number = self._next_pr_number
        self._next_pr_number += 1
        self._open_prs.append(
            {
                "number": number,
                "headRefName": head,
                "baseRefName": base,
                "title": title,
                "body": body,
                "isDraft": draft,
                "state": "OPEN",
                "labels": [],
            }
        )
        self.calls.append(("create_pr", number, head, base, draft, title, body))
        return number

    def find_pr_by_head_branch(self, head: str) -> dict | None:
        for pr in self._open_prs:
            if pr.get("headRefName") == head:
                return dict(pr)
        return None

    def mark_pr_ready(self, number: int) -> None:
        pr = self._pr(number)
        pr["isDraft"] = False
        self.calls.append(("mark_pr_ready", number))

    def add_pr_labels(self, number: int, labels: Sequence[str]) -> None:
        pr = self._pr(number)
        pr["labels"] = _merge_labels(pr.get("labels"), labels)
        self.calls.append(("add_pr_labels", number, tuple(labels)))

    def add_issue_labels(self, number: int, labels: Sequence[str]) -> None:
        issue = self._issue(number)
        issue["labels"] = _merge_labels(issue.get("labels"), labels)
        self.calls.append(("add_issue_labels", number, tuple(labels)))

    def remove_issue_labels(self, number: int, labels: Sequence[str]) -> None:
        issue = self._issue(number)
        drop = set(labels)
        issue["labels"] = [
            label for label in _as_label_objects(issue.get("labels")) if label["name"] not in drop
        ]
        self.calls.append(("remove_issue_labels", number, tuple(labels)))

    def edit_issue_labels(
        self,
        number: int,
        *,
        add: Sequence[str] = (),
        remove: Sequence[str] = (),
    ) -> None:
        issue = self._issue(number)
        drop = set(remove)
        issue["labels"] = [
            label for label in _as_label_objects(issue.get("labels")) if label["name"] not in drop
        ]
        issue["labels"] = _merge_labels(issue.get("labels"), add)
        self.calls.append(("edit_issue_labels", number, tuple(add), tuple(remove)))

    def comment_issue(self, number: int, body: str) -> None:
        issue = self._issue(number)
        comments = list(issue.get("comments") or [])
        comments.append({"author": {"login": "ralph"}, "body": body})
        issue["comments"] = comments
        self.calls.append(("comment_issue", number, body))

    def edit_issue_body(self, number: int, body: str) -> None:
        issue = self._issue(number)
        issue["body"] = body
        self.calls.append(("edit_issue_body", number, body))

    # --- test inspection helpers (not part of the protocol) ---

    def issue_labels(self, number: int) -> set[str]:
        """Current label names on issue ``number`` for assertions."""

        return _label_names(self._issue(number).get("labels"))

    def pr_labels(self, number: int) -> set[str]:
        """Current label names on PR ``number`` for assertions."""

        return _label_names(self._pr(number).get("labels"))

    def pr_is_draft(self, number: int) -> bool:
        """Whether PR ``number`` is still a draft."""

        return bool(self._pr(number).get("isDraft"))

    def _issue(self, number: int) -> dict:
        try:
            return self._issues[int(number)]
        except KeyError as exc:
            raise GitHubClientError(f"no fixture issue #{number}") from exc

    def _pr(self, number: int) -> dict:
        for pr in self._open_prs:
            if pr.get("number") == number:
                return pr
        raise GitHubClientError(f"no PR #{number}")


class GitHubClientError(RuntimeError):
    """Raised when GitHub data cannot be fetched or is malformed."""


def _as_dict_list(payload: object) -> list[dict]:
    if not isinstance(payload, list):
        raise GitHubClientError("expected a JSON array from gh")
    return [dict(item) for item in payload if isinstance(item, Mapping)]


def _as_label_objects(labels: object) -> list[dict]:
    """Normalize a labels field to a list of ``{"name": ...}`` objects."""

    objects: list[dict] = []
    if not isinstance(labels, list):
        return objects
    for label in labels:
        if isinstance(label, Mapping):
            name = label.get("name")
            if isinstance(name, str):
                objects.append({"name": name})
        elif isinstance(label, str):
            objects.append({"name": label})
    return objects


def _merge_labels(existing: object, additions: Sequence[str]) -> list[dict]:
    """Return label objects with ``additions`` appended, de-duplicated by name."""

    objects = _as_label_objects(existing)
    present = {label["name"] for label in objects}
    for name in additions:
        if name not in present:
            objects.append({"name": name})
            present.add(name)
    return objects


def _label_names(labels: object) -> set[str]:
    """Normalize a ``gh`` labels field (list of objects or strings) to a name set."""

    if not isinstance(labels, list):
        return set()
    names: set[str] = set()
    for label in labels:
        if isinstance(label, Mapping):
            name = label.get("name")
            if isinstance(name, str):
                names.add(name)
        elif isinstance(label, str):
            names.add(label)
    return names
