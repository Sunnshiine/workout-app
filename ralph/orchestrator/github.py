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
_ISSUE_VIEW_FIELDS = "number,title,body,labels,comments"
# Fields requested from ``gh pr list`` for branch-reuse lookup.
_PR_LIST_FIELDS = "number,headRefName,state"


@runtime_checkable
class GitHubClient(Protocol):
    """Read-only GitHub seam used by the orchestrator.

    Implementations return plain ``dict``/``list`` JSON shapes (as ``gh``
    produces). Callers validate and normalize those shapes; the client only
    fetches them.
    """

    def view_issue(self, number: int) -> dict:
        """Return the issue JSON for ``number`` (number, title, body, labels, comments)."""

    def list_open_issues(self, *, label: str | None = None) -> list[dict]:
        """Return open issues, optionally filtered by ``label``."""

    def list_open_prs(self, *, head: str | None = None) -> list[dict]:
        """Return open PRs, optionally filtered by head branch ``head``."""


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


class FakeGitHubClient:
    """In-memory ``GitHubClient`` for tests; never touches network or ``gh``.

    Built from fixture dicts keyed by issue number plus a list of open-PR dicts.
    """

    def __init__(
        self,
        *,
        issues: Mapping[int, Mapping] | None = None,
        open_prs: Iterable[Mapping] | None = None,
    ) -> None:
        self._issues: dict[int, dict] = {int(n): dict(v) for n, v in (issues or {}).items()}
        self._open_prs: list[dict] = [dict(p) for p in (open_prs or [])]

    def view_issue(self, number: int) -> dict:
        try:
            return dict(self._issues[int(number)])
        except KeyError as exc:
            raise GitHubClientError(f"no fixture issue #{number}") from exc

    def list_open_issues(self, *, label: str | None = None) -> list[dict]:
        issues = [dict(v) for v in self._issues.values()]
        if label is None:
            return issues
        return [i for i in issues if label in _label_names(i.get("labels"))]

    def list_open_prs(self, *, head: str | None = None) -> list[dict]:
        prs = [dict(p) for p in self._open_prs]
        if head is None:
            return prs
        return [p for p in prs if p.get("headRefName") == head]


class GitHubClientError(RuntimeError):
    """Raised when GitHub data cannot be fetched or is malformed."""


def _as_dict_list(payload: object) -> list[dict]:
    if not isinstance(payload, list):
        raise GitHubClientError("expected a JSON array from gh")
    return [dict(item) for item in payload if isinstance(item, Mapping)]


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
