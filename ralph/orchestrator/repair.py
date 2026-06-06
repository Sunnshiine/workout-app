"""One-time UI-owned repair cycle before blocked escalation.

When a UI-owned gate (UI integration tests or Visual Regression) fails *after
code already exists*, Ralph gets exactly ONE repair cycle before the work is
escalated to a blocked rescue PR. This slice owns that cycle and nothing else:

1. Write a focused repair brief to
   ``ralph/.artifacts/repair/issue-<issue>-ui-gate.md`` (issue contract, target
   branch/PR context, changed files, failing command, a sanitized + capped log
   excerpt, and artifact paths).
2. Run ONE fresh ``repair-ui-gate`` agent context (via :class:`Engine`) in the
   failing integration worktree.
3. If the repair touched production Swift, test files, project files, or package
   configuration, run a ``review-after-repair`` phase before rerunning.
4. Rerun the relevant UI/full gate EXACTLY once.
5. Pass -> the orchestrator ships through the normal successful lifecycle.
   A SECOND UI-owned failure -> the orchestrator escalates to a blocked rescue PR.

The coordinator is decision-only and immutable: it never publishes, never mutates
its inputs, and is hard-capped at a single repair attempt (no infinite retry).
All agent work flows through the injected :class:`Engine`; the gate rerun and the
changed-files lookup are injected seams so tests force first-fail-then-pass vs
fail-twice without touching a real Xcode build or git.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from .blocked import cap_excerpt, redact_secrets
from .contracts import IssueContract
from .engine import Engine, PhaseRequest
from .gates import GATE_VISUAL_REGRESSION, GateResult
from .phase import PhaseResult

# Phase names for the two agent contexts this cycle can run.
PHASE_REPAIR_UI_GATE = "repair-ui-gate"
PHASE_REVIEW_AFTER_REPAIR = "review-after-repair"

# Default timeout (seconds) for a repair/review phase turn. The orchestrator may
# override per call; this keeps a single call site self-contained.
DEFAULT_PHASE_TIMEOUT_SECONDS = 60 * 60

# Path prefixes/files whose change makes a repair "touch reviewable code" and so
# requires ``review-after-repair`` before rerunning the gate. Mirrors
# ``production_swift_changed`` in ``ralph/ralph.sh`` plus explicit test files.
_PRODUCTION_SWIFT_PREFIX = "WorkoutTracker/"
_TEST_FILE_PREFIXES = ("Tests/",)
_PROJECT_AND_PACKAGE_FILES = (
    "Package.swift",
    "project.yml",
    "WorkoutTracker.xcodeproj/project.pbxproj",
)


# Reruns the relevant gate after repair and returns its ``GateResult``. Injected
# so tests script first-fail-then-pass vs fail-twice without a real build.
GateRerun = Callable[[], GateResult]

# Returns the files the repair phase changed in the integration worktree (paths
# relative to the repo root). Injected so tests decide whether review runs.
ChangedFilesProbe = Callable[[], Sequence[str]]


@dataclass(frozen=True)
class RepairOutcome:
    """Immutable result of the one-time repair cycle.

    ``shipped`` is True when the rerun gate passed (orchestrator ships through the
    normal successful lifecycle). When False the orchestrator escalates to a
    blocked rescue PR. The remaining fields are evidence for the blocked report
    and for assertions: whether review ran, the changed files the repair
    produced, the final rerun ``GateResult``, the repair phase result, and the
    brief path written for the agent.
    """

    shipped: bool
    repair_attempted: bool
    review_ran: bool
    changed_files: tuple[str, ...]
    rerun_gate: GateResult
    repair_phase: PhaseResult
    review_phase: PhaseResult | None
    brief_path: Path


def requires_review(changed_files: Sequence[str]) -> bool:
    """True when changed files include production Swift, test, project, or package files.

    A repair that only touches non-reviewable files (logs, screenshots, fixtures
    outside the Swift targets) does not trigger ``review-after-repair``.
    """

    return any(_is_reviewable(path) for path in changed_files)


def repair_brief_relpath(issue_number: int) -> str:
    """Repo-relative path of the repair brief for ``issue_number``."""

    return f"ralph/.artifacts/repair/issue-{issue_number}-ui-gate.md"


class RepairCoordinator:
    """Runs exactly one UI-owned repair cycle, then ships or escalates.

    Collaborators are all injected so nothing here shells out: ``engine`` runs
    the repair / Swift-review phases, ``rerun_gate`` reruns the failing gate once,
    and ``changed_files`` reports what the repair touched. ``repo_root`` anchors
    the brief artifact and ``workdir`` is the failing integration worktree the
    repair agent runs inside.
    """

    def __init__(
        self,
        engine: Engine,
        *,
        repo_root: Path,
        workdir: Path,
        timeout_seconds: int = DEFAULT_PHASE_TIMEOUT_SECONDS,
    ) -> None:
        self._engine = engine
        self._repo_root = Path(repo_root)
        self._workdir = Path(workdir)
        self._timeout_seconds = timeout_seconds

    def run(
        self,
        contract: IssueContract,
        failed_gate: GateResult,
        *,
        rerun_gate: GateRerun,
        changed_files: ChangedFilesProbe,
        target_branch: str,
        existing_pr_number: int | None = None,
        artifact_paths: Sequence[str] = (),
    ) -> RepairOutcome:
        """Run the single repair cycle for a UI-owned ``failed_gate``.

        Writes the repair brief, runs one ``repair-ui-gate`` phase, conditionally
        runs ``review-after-repair`` when the repair touched reviewable
        code, then reruns the gate EXACTLY once. The cycle never loops: a second
        UI-owned failure yields ``shipped=False`` for blocked escalation.
        """

        if not failed_gate.ui_owned:
            raise RepairError(
                f"gate {failed_gate.name!r} is not UI-owned; only UI-owned gate "
                "failures get a repair cycle"
            )

        brief_path = self._write_brief(
            contract,
            failed_gate,
            target_branch=target_branch,
            existing_pr_number=existing_pr_number,
            artifact_paths=artifact_paths,
        )

        repair_phase = self._run_phase(
            PHASE_REPAIR_UI_GATE,
            contract.number,
            self._repair_prompt(contract, failed_gate, brief_path),
        )

        produced = tuple(changed_files())
        review_phase: PhaseResult | None = None
        if requires_review(produced):
            review_phase = self._run_phase(
                PHASE_REVIEW_AFTER_REPAIR,
                contract.number,
                self._review_prompt(contract, produced),
            )

        rerun = rerun_gate()

        return RepairOutcome(
            shipped=rerun.passed,
            repair_attempted=True,
            review_ran=review_phase is not None,
            changed_files=produced,
            rerun_gate=rerun,
            repair_phase=repair_phase,
            review_phase=review_phase,
            brief_path=brief_path,
        )

    def _run_phase(self, phase: str, issue_number: int, prompt: str) -> PhaseResult:
        return self._engine.run_phase(
            PhaseRequest(
                phase=phase,
                prompt=prompt,
                workdir=self._workdir,
                issue_number=issue_number,
                timeout_seconds=self._timeout_seconds,
            )
        )

    def _write_brief(
        self,
        contract: IssueContract,
        failed_gate: GateResult,
        *,
        target_branch: str,
        existing_pr_number: int | None,
        artifact_paths: Sequence[str],
    ) -> Path:
        brief_path = self._repo_root / repair_brief_relpath(contract.number)
        brief_path.parent.mkdir(parents=True, exist_ok=True)
        brief_path.write_text(
            render_repair_brief(
                contract,
                failed_gate,
                target_branch=target_branch,
                existing_pr_number=existing_pr_number,
                artifact_paths=artifact_paths,
            ),
            encoding="utf-8",
        )
        return brief_path

    def _repair_prompt(
        self, contract: IssueContract, failed_gate: GateResult, brief_path: Path
    ) -> str:
        ui_test_rule = _ui_test_edit_rule(contract)
        baseline_rule = ""
        if failed_gate.name == GATE_VISUAL_REGRESSION:
            baseline_rule = " " + _baseline_acceptance_rule()
        return (
            f"You are debugging the UI-owned gate failure for issue "
            f"#{contract.number}. The failing gate is {failed_gate.name!r}. Read "
            f"the repair brief at {brief_path} and fix the failure while staying "
            f"inside the issue acceptance criteria. {ui_test_rule}{baseline_rule}"
        )

    def _review_prompt(self, contract: IssueContract, changed_files: Sequence[str]) -> str:
        return (
            f"Run the review-after-repair phase for issue #{contract.number} before "
            f"the gate reruns. Changed files: {', '.join(changed_files)}. Review "
            "only the repair changes against the frozen issue contract and repair "
            "context. Spawn both read-only reviewer subagents: swift-reviewer for "
            "technical review and spec-conformance-reviewer for issue-contract "
            "conformance. Fix any blocking findings in this worktree, commit "
            "review remediation, and complete only after both reviewers are clean."
        )


class RepairError(RuntimeError):
    """Raised when a repair cycle is asked to run on a non-UI-owned failure."""


def render_repair_brief(
    contract: IssueContract,
    failed_gate: GateResult,
    *,
    target_branch: str,
    existing_pr_number: int | None,
    artifact_paths: Sequence[str],
) -> str:
    """Render the progressive-disclosure repair brief markdown.

    The brief carries the issue contract, target branch/PR context, the failing
    command, a sanitized + capped log excerpt (reusing the blocked-report
    redaction and caps so no secret reaches an artifact), and the local artifact
    paths. Full logs stay referenced by path, never inlined raw.
    """

    pr_line = (
        f"#{existing_pr_number}" if existing_pr_number is not None else "none (not yet created)"
    )
    exit_status = "n/a" if failed_gate.exit_status is None else str(failed_gate.exit_status)
    sections = [
        f"# UI repair brief: issue #{contract.number}",
        "",
        f"{contract.title}".strip(),
        "",
        "## Failure",
        "",
        f"- Failing gate: {failed_gate.name}",
        f"- Failing command: `{redact_secrets(_join_command(failed_gate.command))}`",
        f"- Exit status: {exit_status}",
        "",
        "## Target",
        "",
        f"- Branch: `{target_branch}`",
        f"- Open PR: {pr_line}",
        f"- PRD: {_prd_label(contract)}",
        "",
        "## Issue contract",
        "",
        _issue_contract_block(contract),
    ]
    sections += ["", "## Sanitized log excerpt", "", _excerpt_block(failed_gate)]
    sections += ["", "## Local artifacts", "", _artifacts_block(failed_gate, artifact_paths)]
    sections += [
        "",
        "## Rules",
        "",
        "- Stay inside the issue acceptance criteria.",
        f"- {_ui_test_edit_rule(contract)}",
    ]
    if failed_gate.name == GATE_VISUAL_REGRESSION:
        sections.append(f"- {_baseline_acceptance_rule()}")
    return "\n".join(sections).rstrip() + "\n"


def _ui_test_edit_rule(contract: IssueContract) -> str:
    """Repair-phase UI-test edit rule.

    This phase runs as ``repair-ui-gate`` (NOT ui-verify), so editing
    ``Tests/UI/**`` is permitted ONLY when the issue contract authorizes UI test
    edits; otherwise the agent must not weaken UI tests.
    """

    if contract.ui_test_edits_authorized:
        return (
            "This repair phase MAY edit `Tests/UI/**` because the issue contract "
            "authorizes UI test edits; keep edits minimal and never weaken coverage "
            "beyond what the contract requires."
        )
    return (
        "Do not edit `Tests/UI/**` or otherwise weaken UI tests; the issue contract "
        "does not authorize UI test edits in this repair phase."
    )


def _baseline_acceptance_rule() -> str:
    """Visual Regression baseline-acceptance guidance for the repair phase."""

    return (
        "If the Visual Regression mismatch is caused by an INTENTIONAL view change "
        "required by the issue's acceptance criteria, regenerate/accept the new "
        "snapshot under `Tests/Visual/__Snapshots__/` and commit it. If the change "
        "is NOT called for by the contract, treat it as a real regression and fix "
        "the view instead."
    )


def _issue_contract_block(contract: IssueContract) -> str:
    body = contract.body.strip()
    if not body:
        return "_No issue body captured._"
    return body


def _excerpt_block(failed_gate: GateResult) -> str:
    excerpt = failed_gate.failure_excerpt
    if not excerpt:
        return "_No captured output. See the referenced log._"
    safe = cap_excerpt(redact_secrets(excerpt))
    return "\n".join(["```", safe, "```"])


def _artifacts_block(failed_gate: GateResult, artifact_paths: Sequence[str]) -> str:
    paths: list[str] = []
    if failed_gate.log_path is not None:
        paths.append(str(failed_gate.log_path))
    paths += [str(path) for path in artifact_paths]
    if not paths:
        return "_None recorded. Full logs stay local._"
    rows = ["Full logs stay local and gitignored (never uploaded):", ""]
    rows += [f"- `{path}`" for path in paths]
    return "\n".join(rows)


def _prd_label(contract: IssueContract) -> str:
    return f"#{contract.prd_number}" if contract.prd_number is not None else "none"


def _join_command(command: Sequence[str]) -> str:
    return " ".join(command) if command else "n/a"


def _is_reviewable(path: str) -> bool:
    if path in _PROJECT_AND_PACKAGE_FILES:
        return True
    if path.startswith(_PRODUCTION_SWIFT_PREFIX) and path.endswith(".swift"):
        return True
    return any(path.startswith(prefix) for prefix in _TEST_FILE_PREFIXES)
