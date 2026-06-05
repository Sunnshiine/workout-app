"""Controlled live GitHub dry-run for the Python Ralph replacement gate.

This path intentionally does not run Codex or Claude. It uses ``FakeEngine`` to
prove the parent-owned GitHub lifecycle against a human-created control issue
and a deterministic ``ralph/dry-run/issue-<n>`` branch containing only a docs
evidence file.
"""

from __future__ import annotations

import subprocess
import tempfile
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from time import gmtime, strftime

from .contracts import IssueContract, capture_issue_contract
from .engine import FAKE_ENGINE, Engine, PhaseRequest
from .github import GitHubClient
from .phase import PhaseStatus
from .publish import (
    LABEL_AGENT_IMPLEMENTED,
    LABEL_AGENT_READY_FOR_REVIEW,
    LABEL_READY_FOR_AGENT,
)

DRY_RUN_AUTHORIZATION_LINE = "Ralph live dry-run: authorized"
DRY_RUN_TITLE_PREFIX = "[Ralph dry-run]"
DRY_RUN_BRANCH_PREFIX = "ralph/dry-run/issue-"
DRY_RUN_PHASE = "ralph-live-github-dry-run"
EVIDENCE_DIR = Path("docs/ralph/live-dry-runs")


@dataclass(frozen=True)
class GitCommandResult:
    """Outcome of one dry-run git command."""

    returncode: int
    stdout: str = ""
    stderr: str = ""

    @property
    def ok(self) -> bool:
        return self.returncode == 0


GitCommandRunner = Callable[[Sequence[str], Path], GitCommandResult]


@dataclass(frozen=True)
class LiveDryRunResult:
    """Summary of the controlled dry-run for console output and evidence."""

    issue_number: int
    branch: str
    pr_number: int
    evidence_path: Path
    reused_pr: bool
    marked_ready: bool
    comment_posted: bool


class LiveDryRunError(RuntimeError):
    """Raised when the controlled dry-run cannot proceed safely."""


class SubprocessGitRunner:
    """Git runner rooted at an explicit cwd; production path only."""

    def __call__(self, args: Sequence[str], cwd: Path) -> GitCommandResult:
        completed = subprocess.run(  # noqa: S603 - argv is controlled by this module.
            ["git", *args],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        return GitCommandResult(
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
        )


def run_live_github_dry_run(
    *,
    issue_number: int,
    repo_root: Path,
    client: GitHubClient,
    engine: Engine,
    git: GitCommandRunner | None = None,
    timestamp: str | None = None,
) -> LiveDryRunResult:
    """Execute the issue #213 live dry-run path.

    The control issue must be deliberately marked by title and body. The fake
    engine is invoked once to prove engine selection, but it never edits files.
    GitHub mutations are issue labels, a draft-to-ready PR, and one issue
    comment. The pushed branch contains only the generated evidence markdown.
    """

    if engine.name != FAKE_ENGINE:
        raise LiveDryRunError("live GitHub dry-run must use the fake engine.")

    contract = capture_issue_contract(client, issue_number)
    _validate_control_issue(contract)

    now = timestamp or strftime("%Y-%m-%dT%H:%M:%SZ", gmtime())
    runner = git or SubprocessGitRunner()
    branch = dry_run_branch(issue_number)
    evidence_relpath = evidence_path(issue_number)
    initial_evidence = _render_evidence(
        contract=contract,
        branch=branch,
        pr_number=None,
        reused_pr=False,
        marked_ready=False,
        comment_posted=False,
        timestamp=now,
    )

    phase = engine.run_phase(
        PhaseRequest(
            phase=DRY_RUN_PHASE,
            prompt="Controlled GitHub dry-run only. Do not edit code.",
            workdir=repo_root,
            issue_number=issue_number,
            timeout_seconds=1,
        )
    )
    if phase.status is not PhaseStatus.COMPLETE:
        raise LiveDryRunError(f"fake engine returned {phase.status}.")

    with tempfile.TemporaryDirectory(prefix=f"ralph-dry-run-{issue_number}-") as tmp:
        dry_worktree = Path(tmp) / "worktree"
        try:
            _prepare_branch(
                repo_root=repo_root,
                worktree=dry_worktree,
                branch=branch,
                evidence_relpath=evidence_relpath,
                evidence=initial_evidence,
                git=runner,
            )

            existing = client.find_pr_by_head_branch(branch)
            reused_pr = existing is not None
            pr_number = (
                _pr_number(existing)
                if existing is not None
                else _create_dry_run_pr(
                    client=client,
                    contract=contract,
                    branch=branch,
                )
            )

            client.remove_issue_labels(issue_number, [LABEL_READY_FOR_AGENT])
            client.add_issue_labels(issue_number, [LABEL_AGENT_IMPLEMENTED])

            marked_ready = _mark_pr_ready(client, pr_number, existing)
            client.add_pr_labels(pr_number, [LABEL_AGENT_READY_FOR_REVIEW])

            comment = _render_issue_comment(
                contract=contract,
                branch=branch,
                pr_number=pr_number,
                evidence_relpath=evidence_relpath,
            )
            client.comment_issue(issue_number, comment)

            final_evidence = _render_evidence(
                contract=contract,
                branch=branch,
                pr_number=pr_number,
                reused_pr=reused_pr,
                marked_ready=marked_ready,
                comment_posted=True,
                timestamp=now,
            )
            _write_evidence(repo_root / evidence_relpath, final_evidence)
            _write_evidence(dry_worktree / evidence_relpath, final_evidence)
            _git(dry_worktree, ["add", str(evidence_relpath)], "stage dry-run evidence", runner)
            _git(
                dry_worktree,
                ["commit", "-m", f"docs: update Ralph dry-run evidence for issue #{issue_number}"],
                "commit final dry-run evidence",
                runner,
            )
            _git(
                dry_worktree,
                ["push", "--force-with-lease", "origin", f"HEAD:{branch}"],
                f"push final {branch}",
                runner,
            )
        finally:
            if dry_worktree.exists():
                _git(
                    repo_root,
                    ["worktree", "remove", "--force", str(dry_worktree)],
                    "remove dry-run worktree",
                    runner,
                )

    return LiveDryRunResult(
        issue_number=issue_number,
        branch=branch,
        pr_number=pr_number,
        evidence_path=repo_root / evidence_relpath,
        reused_pr=reused_pr,
        marked_ready=marked_ready,
        comment_posted=True,
    )


def dry_run_branch(issue_number: int) -> str:
    return f"{DRY_RUN_BRANCH_PREFIX}{issue_number}"


def evidence_path(issue_number: int) -> Path:
    return EVIDENCE_DIR / f"issue-{issue_number}.md"


def format_result(result: LiveDryRunResult) -> str:
    return "\n".join(
        [
            "live GitHub dry-run complete:",
            f"  issue:       #{result.issue_number}",
            f"  branch:      {result.branch}",
            f"  pr:          #{result.pr_number}",
            f"  reused-pr:   {result.reused_pr}",
            f"  marked-ready:{result.marked_ready}",
            f"  evidence:    {result.evidence_path}",
        ]
    )


def _validate_control_issue(contract: IssueContract) -> None:
    if not contract.title.startswith(DRY_RUN_TITLE_PREFIX):
        raise LiveDryRunError(f"control issue title must start with {DRY_RUN_TITLE_PREFIX!r}.")
    authorized = any(
        line.strip() == DRY_RUN_AUTHORIZATION_LINE for line in contract.body.splitlines()
    )
    if not authorized:
        raise LiveDryRunError(
            f"control issue body must contain exact line: {DRY_RUN_AUTHORIZATION_LINE}"
        )


def _prepare_branch(
    *,
    repo_root: Path,
    worktree: Path,
    branch: str,
    evidence_relpath: Path,
    evidence: str,
    git: GitCommandRunner,
) -> None:
    _git(repo_root, ["fetch", "origin", "main"], "fetch origin/main", git)
    _git(
        repo_root,
        ["worktree", "add", "--detach", str(worktree), "origin/main"],
        "add dry-run worktree",
        git,
    )
    _write_evidence(worktree / evidence_relpath, evidence)
    _git(worktree, ["add", str(evidence_relpath)], "stage dry-run evidence", git)
    _git(
        worktree,
        ["commit", "-m", "docs: record Ralph dry-run evidence"],
        "commit dry-run evidence",
        git,
    )
    _git(
        worktree,
        ["push", "--force-with-lease", "origin", f"HEAD:{branch}"],
        f"push {branch}",
        git,
    )


def _create_dry_run_pr(*, client: GitHubClient, contract: IssueContract, branch: str) -> int:
    return client.create_pr(
        draft=True,
        base="main",
        head=branch,
        title=f"{DRY_RUN_TITLE_PREFIX} #{contract.number} fake-engine GitHub wiring",
        body=(
            f"Refs #{contract.number}\n\n"
            "Controlled Python Ralph live dry-run. This PR contains only docs "
            "evidence and was created with the fake engine."
        ),
    )


def _mark_pr_ready(client: GitHubClient, pr_number: int, existing: dict | None) -> bool:
    if existing is not None and existing.get("isDraft") is False:
        return False
    client.mark_pr_ready(pr_number)
    return True


def _render_issue_comment(
    *,
    contract: IssueContract,
    branch: str,
    pr_number: int,
    evidence_relpath: Path,
) -> str:
    return "\n".join(
        [
            "Python Ralph live dry-run completed with the fake engine.",
            "",
            f"- Control issue: #{contract.number}",
            f"- Branch: `{branch}`",
            f"- PR: #{pr_number}",
            f"- Evidence: `{evidence_relpath}`",
            "- Real agent invocation: none",
        ]
    )


def _render_evidence(
    *,
    contract: IssueContract,
    branch: str,
    pr_number: int | None,
    reused_pr: bool,
    marked_ready: bool,
    comment_posted: bool,
    timestamp: str,
) -> str:
    pr = f"#{pr_number}" if pr_number is not None else "pending"
    return "\n".join(
        [
            f"# Ralph Live GitHub Dry-Run Evidence: Issue #{contract.number}",
            "",
            f"- Timestamp: {timestamp}",
            f"- Control issue title: {contract.title}",
            f"- Authorization marker: `{DRY_RUN_AUTHORIZATION_LINE}`",
            f"- Engine: `{FAKE_ENGINE}`",
            f"- Branch: `{branch}`",
            f"- Pull request: {pr}",
            f"- Reused existing PR: {reused_pr}",
            f"- Draft-to-ready attempted: {marked_ready}",
            f"- Issue comment posted: {comment_posted}",
            "- Issue labels exercised: remove `ready-for-agent`, add `agent-implemented`",
            "- PR labels exercised: add `agent-ready-for-review`",
            "- Real agent invocation: none",
            "- Pushed file scope: docs evidence only",
            "",
        ]
    )


def _write_evidence(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")


def _git(cwd: Path, args: Sequence[str], what: str, runner: GitCommandRunner) -> None:
    result = runner(list(args), cwd)
    if result.ok:
        return
    detail = result.stderr.strip() or result.stdout.strip()
    raise LiveDryRunError(f"failed to {what} (git exit {result.returncode}): {detail}")


def _pr_number(pr: dict | None) -> int:
    if pr is None:
        raise LiveDryRunError("missing PR record.")
    number = pr.get("number")
    if isinstance(number, bool) or not isinstance(number, int):
        raise LiveDryRunError(f"PR is missing an integer number: {pr!r}")
    return number
