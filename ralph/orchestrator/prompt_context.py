"""Progressive-disclosure prompt context artifacts.

Phase prompts stay small. Instead of embedding full logs, PRD bodies, comments,
screenshots, or prior transcripts, the orchestrator writes a handful of compact
markdown context files and the prompt references them BY PATH. The agent opens
the fuller context only when it actually needs it.

``PromptContextWriter`` writes these artifacts under one run directory:

- ``issue-contract.md``      — the immutable issue snapshot (body + authority).
- ``phase-context.md``       — role, issue, target, allowed actions, the exact
  completion/block contract, and PATHS to fuller context.
- ``gate-failure-summary.md``— a compact, sanitized gate-failure summary that
  points at the full log by path.
- ``repair-brief.md``        — reuses :func:`render_repair_brief` so the brief is
  sanitized and consistent with the repair coordinator's own artifact.
- ``blocked-report.md``      — reuses :class:`BlockedReportWriter` so the local
  copy matches the sanitized rescue-PR body byte for byte.

Nothing here mutates its inputs and nothing shells out: it only renders strings
and writes files under a directory the caller owns.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from .blocked import BlockedReport, BlockedReportWriter, cap_excerpt, redact_secrets
from .contracts import IssueContract
from .gates import GateResult
from .repair import render_repair_brief

# Artifact file names, kept as constants so callers and tests share one source.
ISSUE_CONTRACT_FILE = "issue-contract.md"
PHASE_CONTEXT_FILE = "phase-context.md"
GATE_FAILURE_SUMMARY_FILE = "gate-failure-summary.md"
REPAIR_BRIEF_FILE = "repair-brief.md"
BLOCKED_REPORT_FILE = "blocked-report.md"


@dataclass(frozen=True)
class PhaseContext:
    """Inputs for the phase-context artifact and prompt.

    ``allowed_actions`` is the short list of what the agent may do this phase.
    ``reference_paths`` are the fuller-context paths (full logs, PRD body,
    comments, screenshots, prior transcripts) the prompt points at rather than
    inlining; the agent opens them only when needed.
    """

    role: str
    phase: str
    target_branch: str
    complete_promise_line: str
    blocked_promise_prefix: str
    allowed_actions: tuple[str, ...] = ()
    existing_pr_number: int | None = None
    reference_paths: tuple[str, ...] = ()


class PromptContextWriter:
    """Writes compact context files for one issue run into ``run_dir``.

    The caller owns ``run_dir`` (typically ``ralph/.artifacts/context/issue-<n>``)
    and the directory is created on first write. Each ``write_*`` method returns
    the path it wrote so the prompt can reference it.
    """

    def __init__(self, run_dir: Path) -> None:
        self._run_dir = Path(run_dir)

    @property
    def run_dir(self) -> Path:
        return self._run_dir

    def write_issue_contract(self, contract: IssueContract) -> Path:
        return self._write(ISSUE_CONTRACT_FILE, render_issue_contract(contract))

    def write_phase_context(self, contract: IssueContract, context: PhaseContext) -> Path:
        return self._write(PHASE_CONTEXT_FILE, render_phase_context(contract, context))

    def write_gate_failure_summary(self, failed_gate: GateResult) -> Path:
        return self._write(GATE_FAILURE_SUMMARY_FILE, render_gate_failure_summary(failed_gate))

    def write_repair_brief(
        self,
        contract: IssueContract,
        failed_gate: GateResult,
        *,
        target_branch: str,
        existing_pr_number: int | None = None,
        artifact_paths: Sequence[str] = (),
    ) -> Path:
        body = render_repair_brief(
            contract,
            failed_gate,
            target_branch=target_branch,
            existing_pr_number=existing_pr_number,
            artifact_paths=artifact_paths,
        )
        return self._write(REPAIR_BRIEF_FILE, body)

    def write_blocked_report(self, report: BlockedReport) -> Path:
        return self._write(BLOCKED_REPORT_FILE, BlockedReportWriter().render(report))

    def _write(self, filename: str, body: str) -> Path:
        self._run_dir.mkdir(parents=True, exist_ok=True)
        path = self._run_dir / filename
        path.write_text(body, encoding="utf-8")
        return path


def render_issue_contract(contract: IssueContract) -> str:
    """Render the immutable issue snapshot as a compact context file."""

    prd = f"#{contract.prd_number}" if contract.prd_number is not None else "none"
    ui_auth = "authorized" if contract.ui_test_edits_authorized else "not authorized"
    sections = [
        f"# Issue contract: #{contract.number}",
        "",
        contract.title.strip(),
        "",
        "## Authority",
        "",
        f"- PRD: {prd}",
        f"- UI integration test edits: {ui_auth}",
        f"- Labels: {_labels_line(contract.labels)}",
        "",
        "## Body",
        "",
        _body_block(contract.body),
    ]
    if contract.comments_for_context:
        sections += ["", "## Comments for context", "", _comments_block(contract)]
    return "\n".join(sections).rstrip() + "\n"


def render_phase_context(contract: IssueContract, context: PhaseContext) -> str:
    """Render the phase prompt's compact context.

    Always carries role, issue, target, allowed actions, and the exact
    completion/block contract. Fuller context is referenced by path so the
    prompt never embeds full logs/comments by default.
    """

    pr_line = (
        f"#{context.existing_pr_number}"
        if context.existing_pr_number is not None
        else "none (not yet created)"
    )
    sections = [
        f"# Phase: {context.phase}",
        "",
        "## Role",
        "",
        context.role.strip(),
        "",
        "## Issue",
        "",
        f"- Number: #{contract.number}",
        f"- Title: {contract.title.strip()}",
        f"- Full contract: `{ISSUE_CONTRACT_FILE}`",
        "",
        "## Target",
        "",
        f"- Branch: `{context.target_branch}`",
        f"- Open PR: {pr_line}",
        "",
        "## Allowed actions",
        "",
        _allowed_actions_block(context.allowed_actions),
        "",
        "## Completion / block contract",
        "",
        f"- Emit exactly this line to COMPLETE: `{context.complete_promise_line}`",
        (
            "- To BLOCK, emit a line starting with "
            f"`{context.blocked_promise_prefix}` followed by the reason and "
            "`</promise>`."
        ),
        "- Generic wording such as done or success does not advance the phase.",
        "",
        "## Further context (open only when needed)",
        "",
        _reference_paths_block(context.reference_paths),
    ]
    return "\n".join(sections).rstrip() + "\n"


def render_gate_failure_summary(failed_gate: GateResult) -> str:
    """Render a compact, sanitized gate-failure summary referencing the full log.

    The excerpt is redacted and capped exactly like the blocked report so no
    secret reaches an artifact; the full log stays referenced by path.
    """

    exit_status = "n/a" if failed_gate.exit_status is None else str(failed_gate.exit_status)
    owner = "UI-owned repair cycle" if failed_gate.ui_owned else "not UI-owned"
    sections = [
        f"# Gate failure: {failed_gate.name}",
        "",
        "## Summary",
        "",
        f"- Gate: {failed_gate.name}",
        f"- Status: {failed_gate.status}",
        f"- Failing command: `{redact_secrets(_join_command(failed_gate.command))}`",
        f"- Exit status: {exit_status}",
        f"- Ownership: {owner}",
        "",
        "## Sanitized excerpt",
        "",
        _excerpt_block(failed_gate),
        "",
        "## Full log (open only when needed)",
        "",
        _log_block(failed_gate),
    ]
    return "\n".join(sections).rstrip() + "\n"


def _labels_line(labels: frozenset[str]) -> str:
    return ", ".join(sorted(labels)) if labels else "none"


def _body_block(body: str) -> str:
    stripped = body.strip()
    return stripped if stripped else "_No issue body captured._"


def _comments_block(contract: IssueContract) -> str:
    rows: list[str] = []
    for comment in contract.comments_for_context:
        author = comment.author or "unknown"
        rows.append(f"- @{author}: {comment.body.strip()}")
    return "\n".join(rows)


def _allowed_actions_block(allowed_actions: Sequence[str]) -> str:
    if not allowed_actions:
        return "_No explicit allowances; follow the phase prompt and issue contract._"
    return "\n".join(f"- {action}" for action in allowed_actions)


def _reference_paths_block(reference_paths: Sequence[str]) -> str:
    if not reference_paths:
        return "_None referenced for this phase._"
    rows = ["Referenced by path; not inlined. Open only what you need:", ""]
    rows += [f"- `{path}`" for path in reference_paths]
    return "\n".join(rows)


def _excerpt_block(failed_gate: GateResult) -> str:
    excerpt = failed_gate.failure_excerpt
    if not excerpt:
        return "_No captured output. See the referenced log._"
    safe = cap_excerpt(redact_secrets(excerpt))
    return "\n".join(["```", safe, "```"])


def _log_block(failed_gate: GateResult) -> str:
    if failed_gate.log_path is None:
        return "_None recorded. Full logs stay local._"
    return f"- `{failed_gate.log_path}` (kept locally and gitignored; never uploaded)"


def _join_command(command: Sequence[str]) -> str:
    return " ".join(command) if command else "n/a"
