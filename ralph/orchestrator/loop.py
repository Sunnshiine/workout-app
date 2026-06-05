"""Top-level Ralph issue-processing loop.

This module connects the already-tested Ralph seams into the command that
operators run. The loop polls ``origin/main`` each iteration, selects one
eligible ``ready-for-agent`` issue, runs phase agents in a deterministic PR
branch worktree, gates that branch, and publishes only through pull requests.
"""

from __future__ import annotations

import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .blocked import BlockedReport, BlockedRescuePublisher
from .config import RunConfig
from .contracts import IssueContract, capture_issue_contract
from .diagnosis import (
    DiagnosisAuthorityParse,
    apply_ui_test_authority,
    parse_diagnosis_authority,
    render_authority_comment,
)
from .engine import Engine, PhaseRequest
from .engines import blocked_promise_prefix, complete_promise_line
from .gates import (
    GATE_SWIFT_TEST,
    GATE_SWIFTLINT,
    GATE_UI_INTEGRATION,
    GATE_UNIT_COMPONENT,
    GATE_XCODEGEN,
    CommandResult,
    GateResult,
    GateRunner,
    GateSpec,
    GateStatus,
)
from .github import GitHubClient, _label_names
from .phase import PhaseResult, PhaseStatus
from .prompt_context import PhaseContext, PromptContextWriter
from .publish import (
    LABEL_AGENT_ACTIVE,
    LABEL_AGENT_BLOCKED,
    LABEL_AGENT_IMPLEMENTED,
    LABEL_READY_FOR_AGENT,
    LABEL_READY_FOR_HUMAN,
    ClaimError,
    GitOutcome,
    IssueClaimer,
    IssuePublisher,
    PullRequestPublisher,
)
from .targets import PrTarget, TargetResolver
from .worktree import GitResult, Worktree, WorktreeManager, default_git_runner

ORIGIN_MAIN = "origin/main"
PHASE_DIAGNOSE = "diagnose"
PHASE_DIAGNOSE_FORMAT = "diagnose-format"
PHASE_IMPLEMENT = "implement-tdd"
PHASE_SWIFT_REVIEW = "swift-review"
PHASE_UI_VERIFY = "ui-verify"

BUG_LABEL = "bug"

ARTIFACT_DIR = Path("ralph/.artifacts")
LOG_DIR = ARTIFACT_DIR / "logs"
CONTEXT_DIR = ARTIFACT_DIR / "context"
WORKTREE_DIR = Path(".claude/worktrees")


@dataclass(frozen=True)
class RunSummary:
    """High-level outcome of one Ralph command invocation."""

    iterations_started: int
    issues_selected: tuple[int, ...]
    issues_completed: tuple[int, ...]
    issues_blocked: tuple[int, ...]
    stopped_reason: str


@dataclass(frozen=True)
class SelectedIssue:
    """Issue chosen for one iteration."""

    number: int
    title: str


@dataclass(frozen=True)
class _DiagnosisOutcome:
    """Result of the bug-diagnosis gate for one issue.

    ``blocked_phase`` is set when diagnosis must escalate (failed/blocked phase,
    an unrecoverable authority block, or out-of-scope authority); the caller then
    publishes a blocked rescue PR. Otherwise ``contract`` is the (possibly
    recaptured) contract and ``diagnosis_path`` points at the handoff artifact.
    """

    contract: IssueContract
    diagnosis_path: Path | None = None
    blocked_phase: PhaseResult | None = None


class RalphLoopError(RuntimeError):
    """Raised when the loop cannot safely continue."""


class IssueSelector:
    """Deterministic selector for the ready-for-agent queue."""

    def __init__(self, client: GitHubClient) -> None:
        self._client = client

    def select_next(self) -> SelectedIssue | None:
        candidates: list[tuple[int, int, str]] = []
        for issue in self._client.list_open_issues(label=LABEL_READY_FOR_AGENT):
            number = _issue_number(issue)
            if number is None:
                continue
            full = self._client.view_issue(number)
            if full.get("state", "OPEN") != "OPEN":
                continue
            title = _issue_title(full)
            labels = _label_names(full.get("labels"))
            if LABEL_READY_FOR_AGENT not in labels:
                continue
            if labels & {
                LABEL_AGENT_ACTIVE,
                LABEL_AGENT_IMPLEMENTED,
                LABEL_READY_FOR_HUMAN,
                LABEL_AGENT_BLOCKED,
            }:
                continue
            if title.lower().startswith("prd:"):
                continue
            if not _has_actionable_contract(full):
                continue
            priority = 0 if "bug" in labels else 1
            candidates.append((priority, number, title))
        if not candidates:
            return None
        priority, number, title = min(candidates)
        return SelectedIssue(number=number, title=title)


class OriginMain:
    """Polls ``origin/main`` and resolves the base ref for PR branches."""

    def __init__(
        self,
        repo_root: Path,
        *,
        runner: Callable[[Sequence[str]], GitResult] = default_git_runner,
    ) -> None:
        self._repo_root = Path(repo_root)
        self._runner = runner

    def poll(self) -> None:
        self._git(["fetch", "origin", "main"], "fetch origin/main")
        self._git(
            ["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"],
            "find origin/main",
        )

    def base_ref_for(self, target: PrTarget) -> str:
        self.poll()
        if self._remote_branch_exists(target.branch):
            return f"origin/{target.branch}"
        return ORIGIN_MAIN

    def _remote_branch_exists(self, branch: str) -> bool:
        self._runner(["-C", str(self._repo_root), "fetch", "origin", branch])
        result = self._runner(
            [
                "-C",
                str(self._repo_root),
                "show-ref",
                "--verify",
                "--quiet",
                f"refs/remotes/origin/{branch}",
            ]
        )
        return result.ok

    def _git(self, args: Sequence[str], what: str) -> GitResult:
        result = self._runner(["-C", str(self._repo_root), *args])
        if not result.ok:
            detail = result.stderr.strip() or result.stdout.strip()
            raise RalphLoopError(f"failed to {what}: {detail}")
        return result


class RalphLoop:
    """Coordinates selection, phase execution, gates, and PR-only publication."""

    def __init__(
        self,
        *,
        config: RunConfig,
        repo_root: Path,
        client: GitHubClient,
        engine: Engine,
        selector: IssueSelector | None = None,
        origin_main: OriginMain | None = None,
        worktrees: WorktreeManager | None = None,
        gate_runner_factory: Callable[[Path, int, int], GateRunner] | None = None,
        publish_runner_factory: (
            Callable[[Path], Callable[[Sequence[str]], GitOutcome]] | None
        ) = None,
        git_runner: Callable[[Sequence[str]], GitResult] = default_git_runner,
    ) -> None:
        self._config = config
        self._repo_root = Path(repo_root)
        self._client = client
        self._engine = engine
        self._selector = selector or IssueSelector(client)
        self._origin_main = origin_main or OriginMain(self._repo_root, runner=git_runner)
        self._worktrees = worktrees or WorktreeManager(self._repo_root, runner=git_runner)
        self._gate_runner_factory = gate_runner_factory or _default_gate_runner_factory
        self._publish_runner_factory = publish_runner_factory or _publish_runner_for
        self._target_resolver = TargetResolver(client)
        self._claimer = IssueClaimer(client)

    def run(self) -> RunSummary:
        if not self._config.select_only:
            self._require_clean_worktree()
        self._ensure_artifacts()

        selected: list[int] = []
        completed: list[int] = []
        blocked: list[int] = []
        iterations_started = 0
        stopped_reason = "max-iterations reached"

        for iteration in range(1, self._config.max_iterations + 1):
            iterations_started = iteration
            _ralph_log(f"polling {ORIGIN_MAIN} for iteration {iteration}")
            self._origin_main.poll()
            chosen = self._selector.select_next()
            if chosen is None:
                stopped_reason = "no eligible ready-for-agent issues"
                _ralph_log("no eligible ready-for-agent issues")
                break

            selected.append(chosen.number)
            _ralph_log(f"selected issue #{chosen.number} {chosen.title}".rstrip())
            if self._config.select_only:
                stopped_reason = "select-only"
                contract = capture_issue_contract(self._client, chosen.number)
                target = self._target_resolver.resolve(contract)
                _ralph_log(f"select-only target for issue #{chosen.number}: {target.branch}")
                break
            contract = self._claim_issue(chosen.number)
            _ralph_log(f"issue #{chosen.number} claimed")
            target = self._target_resolver.resolve(contract)

            outcome = self._run_issue(iteration, contract, target)
            if outcome:
                completed.append(contract.number)
            else:
                blocked.append(contract.number)

        return RunSummary(
            iterations_started=iterations_started,
            issues_selected=tuple(selected),
            issues_completed=tuple(completed),
            issues_blocked=tuple(blocked),
            stopped_reason=stopped_reason,
        )

    def _claim_issue(self, issue_number: int) -> IssueContract:
        try:
            return self._claimer.claim(issue_number)
        except ClaimError as error:
            raise RalphLoopError(str(error)) from error

    def _run_issue(self, iteration: int, contract: IssueContract, target: PrTarget) -> bool:
        base_ref = self._origin_main.base_ref_for(target)
        worktree = self._create_worktree(contract, target, base_ref)
        issue_base = self._rev_parse(worktree.path, "HEAD")
        writer = PromptContextWriter(self._repo_root / CONTEXT_DIR / f"issue-{contract.number}")
        writer.write_issue_contract(contract)

        diagnosis_path: Path | None = None
        if BUG_LABEL in contract.labels:
            diagnosis = self._run_diagnosis(
                iteration, contract, target, worktree, issue_base, writer
            )
            if diagnosis.blocked_phase is not None:
                self._publish_blocked(
                    contract, target, worktree, failed_phase=diagnosis.blocked_phase
                )
                return False
            contract = diagnosis.contract
            diagnosis_path = diagnosis.diagnosis_path
            writer.write_issue_contract(contract)

        extra_refs = (str(diagnosis_path),) if diagnosis_path is not None else ()

        ui_phase_base = issue_base
        ui_phase_tip = issue_base
        failed_phase: PhaseResult | None = None
        for phase, prompt_file in (
            (PHASE_IMPLEMENT, "implement.md"),
            (PHASE_SWIFT_REVIEW, "swift-review.md"),
            (PHASE_UI_VERIFY, "ui-verify.md"),
        ):
            if phase == PHASE_UI_VERIFY:
                ui_phase_base = self._rev_parse(worktree.path, "HEAD")
            result = self._run_phase(
                phase,
                prompt_file,
                iteration,
                contract,
                target,
                worktree,
                issue_base,
                writer,
                extra_reference_paths=extra_refs,
                diagnosis_path=diagnosis_path,
            )
            if not result.is_complete:
                failed_phase = result
                break
            if phase == PHASE_UI_VERIFY:
                ui_phase_tip = self._rev_parse(worktree.path, "HEAD")

        issue_tip = self._rev_parse(worktree.path, "HEAD")
        if failed_phase is not None:
            self._publish_blocked(contract, target, worktree, failed_phase=failed_phase)
            return False

        gate_failure = self._run_gates(iteration, contract, worktree.path)
        if gate_failure is not None:
            self._publish_blocked(
                contract,
                target,
                worktree,
                failed_gate=gate_failure,
                issue_base=issue_base,
                issue_tip=issue_tip,
                ui_phase_base=ui_phase_base,
                ui_phase_tip=ui_phase_tip,
            )
            return False

        self._publish_success(contract, target, worktree.path)
        self._cleanup_worktree(worktree)
        return True

    def _create_worktree(
        self, contract: IssueContract, target: PrTarget, base_ref: str
    ) -> Worktree:
        path = self._repo_root / WORKTREE_DIR / f"issue-{contract.number}"
        _ralph_log(f"creating {target.branch} from {base_ref}")
        return self._worktrees.create(path, target.branch, base_ref)

    def _run_phase(
        self,
        phase: str,
        prompt_file: str,
        iteration: int,
        contract: IssueContract,
        target: PrTarget,
        worktree: Worktree,
        issue_base: str,
        writer: PromptContextWriter,
        *,
        extra_reference_paths: tuple[str, ...] = (),
        diagnosis_path: Path | None = None,
    ) -> PhaseResult:
        context = PhaseContext(
            role=f"Run the Ralph {phase} phase for issue #{contract.number}.",
            phase=phase,
            target_branch=target.branch,
            existing_pr_number=target.existing_pr_number,
            complete_promise_line=complete_promise_line(phase),
            blocked_promise_prefix=blocked_promise_prefix(phase),
            allowed_actions=_allowed_actions_for_phase(phase),
            reference_paths=(
                str(writer.write_issue_contract(contract)),
                *extra_reference_paths,
            ),
        )
        context_path = writer.write_phase_context(contract, context)
        prompt = self._phase_prompt(
            phase, prompt_file, contract, worktree, issue_base, context_path, diagnosis_path
        )
        log_path = (
            self._repo_root / LOG_DIR / f"iter-{iteration}-issue-{contract.number}-{phase}.log"
        )
        _ralph_log(f"issue #{contract.number} {phase} started")
        result = self._engine.run_phase(
            PhaseRequest(
                phase=phase,
                prompt=prompt,
                workdir=worktree.path,
                issue_number=contract.number,
                timeout_seconds=self._config.implement_timeout_seconds,
                log_path=log_path,
            )
        )
        _ralph_log(f"issue #{contract.number} {phase} -> {result.status}")
        return result

    def _phase_prompt(
        self,
        phase: str,
        prompt_file: str,
        contract: IssueContract,
        worktree: Worktree,
        issue_base: str,
        context_path: Path,
        diagnosis_path: Path | None = None,
    ) -> str:
        prompt_body = (self._repo_root / "ralph" / "prompts" / prompt_file).read_text(
            encoding="utf-8"
        )
        return "\n".join(
            [
                f"Engine: {self._config.engine}. This is the {phase} phase.",
                f"You are working GitHub issue #{contract.number}.",
                f"You are inside an isolated git worktree at: {worktree.path}",
                f"Branch: {worktree.branch}",
                f"ISSUE_BASE_REF: {issue_base}",
                "PUBLISH_TARGET: pr",
                f"TARGET_BRANCH: {worktree.branch}",
                f"TARGET_PR: {contract.prd_number or ''}",
                f"PHASE_NAME: {phase}",
                f"CONTEXT_PATH: {context_path}",
                f"DIAGNOSIS_PATH: {diagnosis_path}" if diagnosis_path is not None else "",
                f"COMPLETE_PROMISE_LINE: {complete_promise_line(phase)}",
                f"BLOCKED_PROMISE_PREFIX: {blocked_promise_prefix(phase)}",
                "UI_SHOT_PATH: ralph/.artifacts/issue-"
                f"{contract.number}-ui-review.png",
                "UI_REVIEW_PATH: ralph/.artifacts/issue-"
                f"{contract.number}-ui-review.md",
                "OBSERVATIONS_LOG_PATH: "
                f"{self._repo_root / ARTIFACT_DIR / 'observations.md'}",
                "",
                "Read the context artifact above before editing. "
                "The issue contract is frozen there.",
                "",
                prompt_body,
            ]
        )

    def _run_diagnosis(
        self,
        iteration: int,
        contract: IssueContract,
        target: PrTarget,
        worktree: Worktree,
        issue_base: str,
        writer: PromptContextWriter,
    ) -> _DiagnosisOutcome:
        """Run the bug-only diagnosis gate before implementation.

        Runs the ``diagnose`` phase, writes the ``diagnosis.md`` handoff, parses
        the authority block (with one corrective ``diagnose-format`` retry for a
        malformed block), grants UI-test authority only for ``Tests/UI/**``, and
        recaptures the contract. Any unrecoverable step returns a blocked phase so
        the caller escalates to a rescue PR.
        """

        result = self._run_phase(
            PHASE_DIAGNOSE, "diagnose.md", iteration, contract, target, worktree, issue_base, writer
        )
        if not result.is_complete:
            return _DiagnosisOutcome(contract=contract, blocked_phase=result)

        diagnosis_path = writer.write_diagnosis(result.final_response)
        parse = parse_diagnosis_authority(result.final_response)

        if parse.needs_corrective_pass:
            corrective = self._run_phase(
                PHASE_DIAGNOSE_FORMAT,
                "diagnose-format.md",
                iteration,
                contract,
                target,
                worktree,
                issue_base,
                writer,
                extra_reference_paths=(str(diagnosis_path),),
                diagnosis_path=diagnosis_path,
            )
            if not corrective.is_complete:
                return _DiagnosisOutcome(contract=contract, blocked_phase=corrective)
            parse = parse_diagnosis_authority(corrective.final_response)
            if parse.needs_corrective_pass:
                return _DiagnosisOutcome(
                    contract=contract,
                    blocked_phase=_diagnosis_blocked(
                        f"diagnosis authority block still invalid after the corrective pass: "
                        f"{parse.error}"
                    ),
                )
            diagnosis_path = writer.write_diagnosis(
                f"{result.final_response}\n\n## Corrected authority\n\n{corrective.final_response}"
            )

        if parse.needs_human_escalation:
            paths = ", ".join(parse.out_of_scope_paths)
            return _DiagnosisOutcome(
                contract=contract,
                blocked_phase=_diagnosis_blocked(
                    "diagnosis requires test authority beyond Tests/UI/** "
                    f"({paths}); human authority required."
                ),
            )

        contract = self._grant_ui_authority(contract, parse)
        return _DiagnosisOutcome(contract=contract, diagnosis_path=diagnosis_path)

    def _grant_ui_authority(
        self, contract: IssueContract, parse: DiagnosisAuthorityParse
    ) -> IssueContract:
        """Grant ``Tests/UI/**`` edit authority on the issue body when diagnosis asks for it.

        Only acts when diagnosis required UI-test edits and the contract is not
        already authorized. Edits the issue body, records an audit comment, and
        recaptures the contract so implementation reads the granted authority.
        """

        authority = parse.authority
        if authority is None or not authority.ui_integration_test_edits_required:
            return contract
        if contract.ui_test_edits_authorized:
            return contract

        new_body = apply_ui_test_authority(
            contract.body, scope=authority.scope, reason=authority.reason
        )
        self._client.edit_issue_body(contract.number, new_body)
        self._client.comment_issue(
            contract.number,
            render_authority_comment(contract.number, authority.scope, authority.reason),
        )
        print(
            f"Ralph: issue #{contract.number} granted UI integration test authority "
            "during diagnosis",
            flush=True,
        )
        return capture_issue_contract(self._client, contract.number)

    def _run_gates(
        self, iteration: int, contract: IssueContract, workdir: Path
    ) -> GateResult | None:
        runner = self._gate_runner_factory(workdir, iteration, contract.number)
        for result in runner.run_all(_gate_specs(self._config.sim_device)):
            _ralph_log(f"gate {result.name} -> {result.status}")
            if result.status == GateStatus.FAILED:
                return result
        return None

    def _publish_success(self, contract: IssueContract, target: PrTarget, workdir: Path) -> None:
        runner = self._publish_runner_factory(workdir)
        pr_publisher = PullRequestPublisher(self._client, runner)
        issue_publisher = IssuePublisher(self._client)
        pr_number = pr_publisher.publish(contract, target, engine=self._config.engine)
        issue_publisher.mark_implemented(contract.number)
        pr_publisher.update_readiness(contract, pr_number)
        _ralph_log(f"issue #{contract.number} published to PR #{pr_number}")

    def _publish_blocked(
        self,
        contract: IssueContract,
        target: PrTarget,
        worktree: Worktree,
        *,
        failed_phase: PhaseResult | None = None,
        failed_gate: GateResult | None = None,
        issue_base: str | None = None,
        issue_tip: str | None = None,
        ui_phase_base: str | None = None,
        ui_phase_tip: str | None = None,
    ) -> None:
        report = BlockedReport(
            issue=contract.number,
            title=contract.title,
            prd_number=contract.prd_number,
            intended_branch=target.branch,
            failed_phase_or_gate=_failed_name(failed_phase, failed_gate),
            failing_command=" ".join(failed_gate.command) if failed_gate else "",
            exit_status=failed_gate.exit_status if failed_gate else None,
            repair_attempted=False,
            repair_result=None,
            changed_files=self._changed_files(worktree.path, issue_base, issue_tip),
            diffstat=self._diffstat(worktree.path, issue_base, issue_tip),
            sanitized_excerpt=_blocked_excerpt(failed_phase, failed_gate),
            local_artifact_paths=_artifact_paths(failed_phase, failed_gate),
            recommended_next_action=(
                "Inspect the blocked PR and rerun Ralph after resolving the cause."
            ),
        )
        runner = self._publish_runner_factory(worktree.path)
        publisher = BlockedRescuePublisher(self._client, runner)
        plan = publisher.plan(contract)
        _run_git(worktree.path, ["switch", "-C", plan.branch])
        pr_number = publisher.publish(contract, report)
        _ralph_log(f"issue #{contract.number} blocked in PR #{pr_number}")
        # Preserve blocked worktree for inspection; cleanup would defeat the rescue path.
        _ = ui_phase_base, ui_phase_tip

    def _changed_files(
        self, workdir: Path, base: str | None, tip: str | None
    ) -> tuple[str, ...]:
        if not base or not tip:
            return ()
        result = _run_git(workdir, ["diff", "--name-only", base, tip], check=False)
        if not result.ok:
            return ()
        return tuple(line for line in result.stdout.splitlines() if line.strip())

    def _diffstat(self, workdir: Path, base: str | None, tip: str | None) -> str:
        if not base or not tip:
            return ""
        result = _run_git(workdir, ["diff", "--stat", base, tip], check=False)
        return result.stdout.strip() if result.ok else ""

    def _rev_parse(self, workdir: Path, ref: str) -> str:
        result = _run_git(workdir, ["rev-parse", ref])
        return result.stdout.strip()

    def _cleanup_worktree(self, worktree: Worktree) -> None:
        self._worktrees.remove(worktree.path, worktree.branch)

    def _ensure_artifacts(self) -> None:
        for path in (self._repo_root / LOG_DIR, self._repo_root / CONTEXT_DIR):
            path.mkdir(parents=True, exist_ok=True)
        activity = self._repo_root / ARTIFACT_DIR / "activity.md"
        if not activity.exists():
            activity.write_text("# Ralph Activity Log\n\n", encoding="utf-8")
        observations = self._repo_root / ARTIFACT_DIR / "observations.md"
        if not observations.exists():
            observations.write_text("# Ralph Observations\n\n", encoding="utf-8")

    def _require_clean_worktree(self) -> None:
        result = default_git_runner(["-C", str(self._repo_root), "status", "--porcelain"])
        if not result.ok:
            detail = result.stderr.strip() or result.stdout.strip()
            raise RalphLoopError(f"could not inspect working tree status: {detail}")
        if result.stdout.strip():
            raise RalphLoopError("working tree is dirty; refusing to run mutating phases.")


def _default_gate_runner_factory(workdir: Path, iteration: int, issue_number: int) -> GateRunner:
    logs = Path(workdir) / LOG_DIR
    logs.mkdir(parents=True, exist_ok=True)

    def log_path_for(name: str) -> Path:
        return logs / f"iter-{iteration}-issue-{issue_number}-{name}.log"

    def run(command: Sequence[str]) -> CommandResult:
        completed = subprocess.run(  # noqa: S603 - commands are fixed gate specs.
            list(command),
            cwd=workdir,
            capture_output=True,
            text=True,
            check=False,
        )
        output = completed.stdout + completed.stderr
        if command:
            gate_name = _gate_name_for_command(command)
            log_path_for(gate_name).write_text(output, encoding="utf-8")
        return CommandResult(exit_status=completed.returncode, output=output)

    return GateRunner(run, log_path_for=log_path_for)


def _ralph_log(message: str) -> None:
    print(_format_ralph_log_line(message), flush=True)


def _format_ralph_log_line(message: str, *, now: datetime | None = None) -> str:
    timestamp = now or datetime.now().astimezone()
    if timestamp.tzinfo is None:
        timestamp = timestamp.astimezone()
    return f"{timestamp.isoformat(timespec='seconds')} | Ralph: {message}"


def _gate_specs(device: str) -> tuple[GateSpec, ...]:
    destination = f"platform=iOS Simulator,name={device}"
    return (
        GateSpec(GATE_SWIFT_TEST, ("swift", "test")),
        GateSpec(GATE_XCODEGEN, ("xcodegen", "generate")),
        GateSpec(
            GATE_UNIT_COMPONENT,
            (
                "xcodebuild",
                "-project",
                "WorkoutTracker.xcodeproj",
                "-scheme",
                "WorkoutTracker",
                "-configuration",
                "Debug",
                "-destination",
                destination,
                "-derivedDataPath",
                ".ralph-dd",
                "test",
                "-only-testing:WorkoutTrackerTests",
            ),
        ),
        GateSpec(
            GATE_UI_INTEGRATION,
            (
                "xcodebuild",
                "-project",
                "WorkoutTracker.xcodeproj",
                "-scheme",
                "WorkoutTracker",
                "-configuration",
                "Debug",
                "-destination",
                destination,
                "-derivedDataPath",
                ".ralph-dd",
                "test",
                "-only-testing:WorkoutTrackerUITests",
            ),
        ),
        GateSpec(GATE_SWIFTLINT, ("swiftlint", "lint", "--quiet")),
    )


def _gate_name_for_command(command: Sequence[str]) -> str:
    if tuple(command) == ("swift", "test"):
        return GATE_SWIFT_TEST
    if tuple(command) == ("xcodegen", "generate"):
        return GATE_XCODEGEN
    if tuple(command) == ("swiftlint", "lint", "--quiet"):
        return GATE_SWIFTLINT
    if "-only-testing:WorkoutTrackerTests" in command:
        return GATE_UNIT_COMPONENT
    if "-only-testing:WorkoutTrackerUITests" in command:
        return GATE_UI_INTEGRATION
    return command[0] if command else "gate"


def _publish_runner_for(workdir: Path) -> Callable[[Sequence[str]], GitOutcome]:
    def run(args: Sequence[str]) -> GitOutcome:
        result = _run_git(workdir, args, check=False)
        return GitOutcome(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)

    return run


def _run_git(workdir: Path, args: Sequence[str], *, check: bool = True) -> GitResult:
    completed = subprocess.run(  # noqa: S603 - git argv is controlled by this module.
        ["git", "-C", str(workdir), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    result = GitResult(
        args=tuple(args),
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )
    if check and not result.ok:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RalphLoopError(f"git {' '.join(args)} failed: {detail}")
    return result


def _diagnosis_blocked(reason: str) -> PhaseResult:
    """Synthesize a blocked ``diagnose`` phase result for escalation paths."""

    return PhaseResult(
        phase=PHASE_DIAGNOSE,
        status=PhaseStatus.BLOCKED,
        final_response=reason,
        blocked_reason=reason,
    )


def _allowed_actions_for_phase(phase: str) -> tuple[str, ...]:
    if phase == PHASE_DIAGNOSE:
        return (
            "reproduce the bug and build a feedback loop",
            "investigate with scratch edits/instrumentation (do not commit)",
            "write a fix plan and the diagnosis-authority block",
        )
    if phase == PHASE_DIAGNOSE_FORMAT:
        return ("re-emit only a corrected diagnosis-authority block from existing findings",)
    if phase == PHASE_IMPLEMENT:
        return ("implement the issue", "commit implementation changes", "run non-UI checks")
    if phase == PHASE_SWIFT_REVIEW:
        return ("review issue diff", "fix blocking non-UI findings", "commit review fixes")
    if phase == PHASE_UI_VERIFY:
        return ("run UI verification", "capture required screenshots", "commit UI fixes")
    return ()


def _issue_number(issue: dict) -> int | None:
    number = issue.get("number")
    if isinstance(number, bool) or not isinstance(number, int):
        return None
    return number


def _issue_title(issue: dict) -> str:
    title = issue.get("title")
    return title if isinstance(title, str) else ""


def _has_actionable_contract(issue: dict) -> bool:
    body = issue.get("body")
    if isinstance(body, str) and body.strip():
        return True
    comments = issue.get("comments")
    if not isinstance(comments, list):
        return False
    for comment in comments:
        if not isinstance(comment, dict):
            continue
        text = comment.get("body")
        if isinstance(text, str) and "Agent Brief" in text:
            return True
    return False


def _failed_name(failed_phase: PhaseResult | None, failed_gate: GateResult | None) -> str:
    if failed_phase is not None:
        return failed_phase.phase
    if failed_gate is not None:
        return failed_gate.name
    return "unknown"


def _blocked_excerpt(failed_phase: PhaseResult | None, failed_gate: GateResult | None) -> str:
    if failed_phase is not None:
        return failed_phase.blocked_reason or failed_phase.final_response
    if failed_gate is not None:
        return failed_gate.failure_excerpt or ""
    return ""


def _artifact_paths(
    failed_phase: PhaseResult | None, failed_gate: GateResult | None
) -> tuple[str, ...]:
    paths: list[str] = []
    if failed_phase is not None and failed_phase.log_path is not None:
        paths.append(str(failed_phase.log_path))
    if failed_gate is not None and failed_gate.log_path is not None:
        paths.append(str(failed_gate.log_path))
    return tuple(paths)
