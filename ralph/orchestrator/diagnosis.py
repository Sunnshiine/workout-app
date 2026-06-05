"""Bug-diagnosis authority parsing and issue-body authority grants.

A bug-labelled issue runs a ``diagnose`` phase before implementation. The phase
emits a structured ``<diagnosis-authority>`` block declaring whether the fix
needs UI integration test edits. This module is the pure, side-effect-free core
of that gate:

- :func:`parse_diagnosis_authority` reads the block out of a diagnosis response
  and classifies it: not-required, grant-UI-tests, malformed (one corrective
  retry), or out-of-scope (escalate for human authority).
- :func:`apply_ui_test_authority` is the pure issue-body transform that adds the
  exact ``UI integration test edits: authorized`` marker under a ``## Test
  authority`` section without ever mutating its input.
- :func:`render_authority_comment` renders the audit comment Ralph posts when it
  grants authority.

The orchestration (running the phase, recapturing the contract, escalating) lives
in ``loop.py``; nothing here shells out, edits GitHub, or mutates its inputs.
"""

from __future__ import annotations

import enum
import re
from collections.abc import Sequence
from dataclasses import dataclass

from .contracts import UI_TEST_AUTHORIZATION_LINE, parse_ui_test_authorization

# Only paths under this prefix can be autonomously authorized by diagnosis.
# Mirrors ``authority.UI_TEST_PATH_PREFIX``; anything else requires human authority.
UI_TEST_PATH_PREFIX = "Tests/UI/"

# Heading that holds the durable authority marker in the issue body.
TEST_AUTHORITY_HEADING = "## Test authority"

_BLOCK = re.compile(
    r"<diagnosis-authority>(?P<inner>.*?)</diagnosis-authority>",
    re.DOTALL,
)
_REQUIRED_KEY = "ui_integration_test_edits_required"
# scope paths are separated by commas and/or whitespace.
_SCOPE_SPLIT = re.compile(r"[,\s]+")


class DiagnosisAuthorityStatus(enum.Enum):
    """Classification of a parsed diagnosis-authority block."""

    NOT_REQUIRED = "not-required"
    """Valid block; ``ui_integration_test_edits_required: false``."""

    GRANT_UI_TESTS = "grant-ui-tests"
    """Valid block requesting authority limited to ``Tests/UI/**``."""

    MALFORMED = "malformed"
    """Block missing, incomplete, or non-boolean; gets one corrective retry."""

    OUT_OF_SCOPE = "out-of-scope"
    """Requests authority beyond ``Tests/UI/**``; must escalate for a human."""

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class DiagnosisAuthority:
    """The validated contents of a diagnosis-authority block."""

    ui_integration_test_edits_required: bool
    scope: tuple[str, ...] = ()
    reason: str = ""


@dataclass(frozen=True)
class DiagnosisAuthorityParse:
    """Outcome of parsing a diagnosis-authority block."""

    status: DiagnosisAuthorityStatus
    authority: DiagnosisAuthority | None = None
    error: str | None = None
    out_of_scope_paths: tuple[str, ...] = ()

    @property
    def is_valid(self) -> bool:
        return self.status in (
            DiagnosisAuthorityStatus.NOT_REQUIRED,
            DiagnosisAuthorityStatus.GRANT_UI_TESTS,
        )

    @property
    def needs_corrective_pass(self) -> bool:
        return self.status is DiagnosisAuthorityStatus.MALFORMED

    @property
    def needs_human_escalation(self) -> bool:
        return self.status is DiagnosisAuthorityStatus.OUT_OF_SCOPE


def parse_diagnosis_authority(text: str) -> DiagnosisAuthorityParse:
    """Parse the first ``<diagnosis-authority>`` block out of ``text``.

    Classifies the block per the spec: a boolean ``ui_integration_test_edits_required``
    line is mandatory; ``true`` additionally requires a non-empty ``scope`` (paths
    only under ``Tests/UI/**``) and a non-empty ``reason``. Scope outside
    ``Tests/UI/**`` is reported as :attr:`DiagnosisAuthorityStatus.OUT_OF_SCOPE` so
    the caller escalates rather than retries.
    """

    match = _BLOCK.search(text)
    if match is None:
        return _malformed("no <diagnosis-authority> block was found")

    fields = _parse_fields(match.group("inner"))
    raw_required = fields.get(_REQUIRED_KEY)
    if raw_required is None:
        return _malformed(f"missing required field `{_REQUIRED_KEY}`")

    required = _parse_bool(raw_required)
    if required is None:
        return _malformed(
            f"`{_REQUIRED_KEY}` must be exactly `true` or `false`, got {raw_required!r}"
        )

    if not required:
        return DiagnosisAuthorityParse(
            status=DiagnosisAuthorityStatus.NOT_REQUIRED,
            authority=DiagnosisAuthority(ui_integration_test_edits_required=False),
        )

    scope = _parse_scope(fields.get("scope", ""))
    reason = fields.get("reason", "").strip()
    if not scope:
        return _malformed("`scope` is required when UI integration test edits are required")
    if not reason:
        return _malformed("`reason` is required when UI integration test edits are required")

    out_of_scope = tuple(path for path in scope if not _under_ui_tests(path))
    if out_of_scope:
        return DiagnosisAuthorityParse(
            status=DiagnosisAuthorityStatus.OUT_OF_SCOPE,
            authority=DiagnosisAuthority(
                ui_integration_test_edits_required=True,
                scope=scope,
                reason=reason,
            ),
            out_of_scope_paths=out_of_scope,
        )

    return DiagnosisAuthorityParse(
        status=DiagnosisAuthorityStatus.GRANT_UI_TESTS,
        authority=DiagnosisAuthority(
            ui_integration_test_edits_required=True,
            scope=scope,
            reason=reason,
        ),
    )


def apply_ui_test_authority(body: str, *, scope: Sequence[str], reason: str) -> str:
    """Return a copy of ``body`` carrying the UI-test authorization marker.

    Idempotent: if the exact marker line is already present the body is returned
    unchanged. Otherwise the marker plus the diagnosis ``scope`` and ``reason`` are
    appended under an existing ``## Test authority`` section, or a new one if the
    body has none. Never mutates ``body``.
    """

    if parse_ui_test_authorization(body):
        return body

    grant_lines = [
        UI_TEST_AUTHORIZATION_LINE,
        f"Diagnosis scope: {', '.join(scope)}" if scope else "Diagnosis scope:",
        f"Diagnosis reason: {reason}" if reason else "Diagnosis reason:",
    ]

    lines = body.splitlines()
    heading_index = _heading_index(lines)
    if heading_index is None:
        prefix = body.rstrip("\n")
        block = "\n".join([TEST_AUTHORITY_HEADING, "", *grant_lines])
        return f"{prefix}\n\n{block}\n" if prefix else f"{block}\n"

    insert_at = _section_insert_index(lines, heading_index)
    updated = [*lines[:insert_at], *grant_lines, *lines[insert_at:]]
    trailing = "\n" if body.endswith("\n") else ""
    return "\n".join(updated) + trailing


def render_authority_comment(issue_number: int, scope: Sequence[str], reason: str) -> str:
    """Render the audit comment recording an autonomous UI-test authority grant."""

    scope_text = ", ".join(scope) if scope else "Tests/UI/**"
    return "\n".join(
        [
            "**Ralph diagnosis — UI integration test edit authority granted**",
            "",
            f"Bug diagnosis for issue #{issue_number} determined that the fix requires "
            "UI integration test edits.",
            "",
            f"- Scope: {scope_text}",
            f"- Reason: {reason}",
            "",
            "The issue body is the durable authority source; this comment is the "
            "state-machine audit event. Authority is limited to `Tests/UI/**`.",
        ]
    )


def _parse_fields(inner: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for raw in inner.splitlines():
        line = raw.strip()
        if not line or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip().lower()
        if key and key not in fields:
            fields[key] = value.strip()
    return fields


def _parse_bool(value: str) -> bool | None:
    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    return None


def _parse_scope(value: str) -> tuple[str, ...]:
    return tuple(token for token in _SCOPE_SPLIT.split(value.strip()) if token)


def _under_ui_tests(path: str) -> bool:
    return path.startswith(UI_TEST_PATH_PREFIX)


def _heading_index(lines: Sequence[str]) -> int | None:
    for index, line in enumerate(lines):
        if line.strip().lower() == TEST_AUTHORITY_HEADING.lower():
            return index
    return None


def _section_insert_index(lines: Sequence[str], heading_index: int) -> int:
    """Index just past the ``## Test authority`` section's existing content.

    Inserts before the next ``##`` heading (or end of body), keeping the new
    marker lines inside the section.
    """

    for index in range(heading_index + 1, len(lines)):
        if lines[index].lstrip().startswith("## "):
            return index
    return len(lines)


def _malformed(reason: str) -> DiagnosisAuthorityParse:
    return DiagnosisAuthorityParse(status=DiagnosisAuthorityStatus.MALFORMED, error=reason)


__all__ = [
    "DiagnosisAuthority",
    "DiagnosisAuthorityParse",
    "DiagnosisAuthorityStatus",
    "TEST_AUTHORITY_HEADING",
    "UI_TEST_PATH_PREFIX",
    "apply_ui_test_authority",
    "parse_diagnosis_authority",
    "render_authority_comment",
]
