"""Pre-agent issue contract snapshot.

The contract is captured from a ``GitHubClient`` BEFORE any mutating agent phase
runs. All later authority checks (PRD membership, UI-test edit authority) read
this immutable snapshot, never live comments or a re-fetched issue. PRD and
UI-test authority come only from the issue BODY at snapshot time; comments,
Agent Briefs, and later body edits are deliberately ignored.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .github import GitHubClient, GitHubClientError, _label_names

# Exact line that authorizes Tests/UI/** edits. Matched as a whole stripped line,
# not a fuzzy substring, so prose merely mentioning UI tests never grants it.
UI_TEST_AUTHORIZATION_LINE = "UI integration test edits: authorized"

# ``PRD: #<number>`` directive in the body. Anchored to a line so an inline
# mention inside prose does not register as membership.
_PRD_DIRECTIVE = re.compile(r"^\s*PRD:\s*#(\d+)\s*$", re.MULTILINE)

# ``## Blocked by`` section header. Anchored to a line so the dependency list is
# scoped from this heading until the next ``##`` heading (or EOF); ``#<number>``
# mentions elsewhere in the body (e.g. ``Refs #222``) never register as a dep.
_BLOCKED_BY_HEADING = re.compile(r"^\s*##\s+Blocked by\s*$", re.IGNORECASE | re.MULTILINE)
_NEXT_HEADING = re.compile(r"^\s*##\s", re.MULTILINE)
_ISSUE_REFERENCE = re.compile(r"#(\d+)")


@dataclass(frozen=True)
class IssueComment:
    """A single issue comment kept only for agent context (never authority)."""

    author: str
    body: str


@dataclass(frozen=True)
class IssueContract:
    """Immutable snapshot of an issue taken before mutating agent work."""

    number: int
    title: str
    body: str
    labels: frozenset[str] = field(default_factory=frozenset)
    comments_for_context: tuple[IssueComment, ...] = ()
    prd_number: int | None = None
    ui_test_edits_authorized: bool = False
    blocked_by: tuple[int, ...] = ()


def capture_issue_contract(client: GitHubClient, number: int) -> IssueContract:
    """Snapshot issue ``number`` into an immutable :class:`IssueContract`.

    Reads exactly once through the GitHub seam. PRD membership and UI-test edit
    authority are derived solely from the body at this instant.
    """

    payload = client.view_issue(number)

    body = _require_str(payload.get("body"), default="")
    title = _require_str(payload.get("title"), default="")
    resolved_number = _coerce_number(payload.get("number"), fallback=number)

    return IssueContract(
        number=resolved_number,
        title=title,
        body=body,
        labels=frozenset(_label_names(payload.get("labels"))),
        comments_for_context=_parse_comments(payload.get("comments")),
        prd_number=parse_prd_number(body),
        ui_test_edits_authorized=parse_ui_test_authorization(body),
        blocked_by=parse_blocked_by(body),
    )


def parse_prd_number(body: str) -> int | None:
    """Return the PRD number from an explicit ``PRD: #<number>`` body line.

    Only the issue body grants membership. The first matching directive wins;
    None when no directive line is present.
    """

    match = _PRD_DIRECTIVE.search(body)
    return int(match.group(1)) if match else None


def parse_blocked_by(body: str) -> tuple[int, ...]:
    """Return upstream issue numbers from a ``## Blocked by`` body section.

    Numbers are read only from within that section (from the heading until the
    next ``##`` heading or EOF), so a ``#222`` mention elsewhere in the body does
    not register as a dependency. Order is preserved and duplicates removed.
    """

    heading = _BLOCKED_BY_HEADING.search(body)
    if heading is None:
        return ()

    section_start = heading.end()
    next_heading = _NEXT_HEADING.search(body, section_start)
    section_end = next_heading.start() if next_heading else len(body)
    section = body[section_start:section_end]

    seen: dict[int, None] = {}
    for match in _ISSUE_REFERENCE.finditer(section):
        seen.setdefault(int(match.group(1)), None)
    return tuple(seen)


def parse_ui_test_authorization(body: str) -> bool:
    """True only when a stripped body line equals the exact authorization line."""

    return any(line.strip() == UI_TEST_AUTHORIZATION_LINE for line in body.splitlines())


def _parse_comments(raw: object) -> tuple[IssueComment, ...]:
    if not isinstance(raw, list):
        return ()
    comments: list[IssueComment] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        comments.append(
            IssueComment(
                author=_comment_author(item.get("author")),
                body=_require_str(item.get("body"), default=""),
            )
        )
    return tuple(comments)


def _comment_author(author: object) -> str:
    if isinstance(author, dict):
        login = author.get("login")
        return login if isinstance(login, str) else ""
    return author if isinstance(author, str) else ""


def _require_str(value: object, *, default: str) -> str:
    return value if isinstance(value, str) else default


def _coerce_number(value: object, *, fallback: int) -> int:
    if isinstance(value, bool):
        raise GitHubClientError("issue number must be an integer, not a bool")
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return fallback
