"""Bug-diagnosis artifact parsing and issue-body authority grants.

A bug-labelled issue runs a ``diagnose`` (reasoning) phase, then a dedicated
``diagnose-extract`` phase whose sole job is to emit a single structured
``<diagnosis-result>`` artifact — a JSON object carrying the full handoff (root
cause, fix plan, regression-test seam) plus the UI-test authority decision.
This module is the pure, side-effect-free core of that gate:

- :func:`parse_diagnosis_authority` reads the artifact out of an extraction
  response and classifies it: not-required, grant-UI-tests, malformed (re-runs
  only the cheap ``diagnose-extract`` turn), or out-of-scope (escalate for
  human authority).
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
import json
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
    r"<diagnosis-result>(?P<inner>.*?)</diagnosis-result>",
    re.DOTALL,
)
_REQUIRED_KEY = "ui_integration_test_edits_required"
# Handoff fields that must be present and non-empty for a well-formed artifact.
_HANDOFF_KEYS = ("root_cause", "fix_plan", "test_seam")


class DiagnosisAuthorityStatus(enum.Enum):
    """Classification of a parsed diagnosis artifact."""

    NOT_REQUIRED = "not-required"
    """Valid artifact; ``ui_integration_test_edits_required: false``."""

    GRANT_UI_TESTS = "grant-ui-tests"
    """Valid artifact requesting authority limited to ``Tests/UI/**``."""

    MALFORMED = "malformed"
    """Artifact missing, non-JSON, or schema-invalid; gets a ``diagnose-extract`` retry."""

    OUT_OF_SCOPE = "out-of-scope"
    """Requests authority beyond ``Tests/UI/**``; must escalate for a human."""

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class DiagnosisAuthority:
    """The validated contents of a diagnosis artifact."""

    ui_integration_test_edits_required: bool
    root_cause: str = ""
    fix_plan: str = ""
    test_seam: str = ""
    scope: tuple[str, ...] = ()
    reason: str = ""
    blocked_reason: str = ""


@dataclass(frozen=True)
class DiagnosisAuthorityParse:
    """Outcome of parsing a diagnosis artifact."""

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
    """Parse the first ``<diagnosis-result>`` artifact out of ``text``.

    The artifact body is a JSON object. Classifies it per the spec:
    ``root_cause``, ``fix_plan``, and ``test_seam`` must be present and
    non-empty strings, and a boolean ``ui_integration_test_edits_required`` is
    mandatory; ``true`` additionally requires a non-empty ``scope`` array
    (paths only under ``Tests/UI/**``) and a non-empty ``reason``. Scope
    outside ``Tests/UI/**`` is reported as
    :attr:`DiagnosisAuthorityStatus.OUT_OF_SCOPE` so the caller escalates
    rather than retries. Non-JSON or non-object content is ``MALFORMED``.
    """

    match = _BLOCK.search(text)
    if match is None:
        return _malformed("no <diagnosis-result> artifact was found")

    try:
        payload = json.loads(match.group("inner").strip())
    except json.JSONDecodeError as exc:
        return _malformed(f"<diagnosis-result> body is not valid JSON: {exc}")

    if not isinstance(payload, dict):
        return _malformed("<diagnosis-result> body must be a JSON object")

    for key in _HANDOFF_KEYS:
        value = payload.get(key)
        if not isinstance(value, str) or not value.strip():
            return _malformed(f"missing required field `{key}`")

    if _REQUIRED_KEY not in payload:
        return _malformed(f"missing required field `{_REQUIRED_KEY}`")

    raw_required = payload.get(_REQUIRED_KEY)
    if not isinstance(raw_required, bool):
        return _malformed(
            f"`{_REQUIRED_KEY}` must be a JSON boolean (`true`/`false`), got {raw_required!r}"
        )
    required = raw_required

    handoff = {key: payload[key].strip() for key in _HANDOFF_KEYS}
    raw_blocked_reason = payload.get("blocked_reason", "")
    blocked_reason = raw_blocked_reason.strip() if isinstance(raw_blocked_reason, str) else ""

    if not required:
        return DiagnosisAuthorityParse(
            status=DiagnosisAuthorityStatus.NOT_REQUIRED,
            authority=DiagnosisAuthority(
                ui_integration_test_edits_required=False,
                blocked_reason=blocked_reason,
                **handoff,
            ),
        )

    scope = _parse_scope(payload.get("scope"))
    raw_reason = payload.get("reason", "")
    reason = raw_reason.strip() if isinstance(raw_reason, str) else ""
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
                blocked_reason=blocked_reason,
                **handoff,
            ),
            out_of_scope_paths=out_of_scope,
        )

    return DiagnosisAuthorityParse(
        status=DiagnosisAuthorityStatus.GRANT_UI_TESTS,
        authority=DiagnosisAuthority(
            ui_integration_test_edits_required=True,
            scope=scope,
            reason=reason,
            blocked_reason=blocked_reason,
            **handoff,
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


def _parse_scope(value: object) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    if not all(isinstance(item, str) and item.strip() for item in value):
        return ()
    return tuple(item.strip() for item in value)


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
