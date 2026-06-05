"""Blocked rescue PRs and sanitized failure reports.

When Ralph produced code but a later phase, gate, or policy check fails, the work
is preserved in a *separate* draft rescue PR instead of being lost in a local
worktree or pushed onto a clean PRD stack branch. This slice owns:

- :class:`BlockedReport`: the immutable structured summary of a block.
- :class:`BlockedReportWriter`: renders that report into a SANITIZED GitHub body.
  Full raw logs and ``Secrets.xcconfig`` are never published; secret-looking
  values are redacted and excerpts are capped by both line and byte count.
- :class:`BlockedRescuePublisher`: commits + pushes the preserved tree to
  ``ralph/issue-<issue>-blocked``, creates a draft PR that refs (never closes)
  the issue, and applies the blocked issue-label transition.

All GitHub mutations flow through the :class:`GitHubClient` seam and all git
operations through the publish git runner, so tests never touch real ``gh``,
real git, or the network.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass

from .contracts import IssueContract
from .github import GitHubClient
from .publish import (
    LABEL_AGENT_BLOCKED,
    LABEL_READY_FOR_AGENT,
    LABEL_READY_FOR_HUMAN,
    GitRunner,
    PublishError,
)
from .targets import _PRD_BRANCH_PREFIX, BASE_BRANCH

# Excerpt caps (spec "Sanitized blocked report"): published excerpts are bounded
# by BOTH a line count and a byte count, whichever is hit first.
MAX_EXCERPT_LINES = 40
MAX_EXCERPT_BYTES = 4000

# Placeholder substituted for any redacted secret value.
REDACTION_PLACEHOLDER = "[REDACTED]"

# Filename whose contents must never reach GitHub.
SECRETS_FILENAME = "Secrets.xcconfig"

# Key-name patterns whose assigned values are redacted before publishing. Each
# entry is a fragment matched against an uppercased key token; ``*`` is a
# wildcard suffix/prefix already implied by substring matching here.
_REDACT_KEY_FRAGMENTS: tuple[str, ...] = (
    "_TOKEN",
    "_SECRET",
    "_KEY",
    "PASSWORD",
    "OPENAI_API_KEY",
    "CODEX_API_KEY",
    "GH_TOKEN",
    "GITHUB_TOKEN",
)
# ``GOOGLE_*`` redacts any key beginning with ``GOOGLE_``.
_REDACT_KEY_PREFIXES: tuple[str, ...] = ("GOOGLE_",)

# Matches ``KEY=value`` / ``KEY: value`` / ``KEY = "value"`` assignments. The key
# token is letters/digits/underscores; the value runs to end of line.
_ASSIGNMENT = re.compile(
    r"^(?P<indent>\s*)(?P<key>[A-Za-z_][A-Za-z0-9_]*)(?P<sep>\s*[:=]\s*)(?P<value>.+)$"
)


@dataclass(frozen=True)
class BlockedReport:
    """Immutable structured summary of a blocked Ralph run.

    Mirrors the spec "Sanitized blocked report" shape. Holds raw context; the
    sanitization (redaction + capping) happens at render time in
    :class:`BlockedReportWriter`, never by mutating this object.
    """

    issue: int
    title: str
    prd_number: int | None
    intended_branch: str
    failed_phase_or_gate: str
    failing_command: str
    exit_status: int | None
    repair_attempted: bool
    repair_result: str | None
    changed_files: tuple[str, ...] = ()
    diffstat: str = ""
    sanitized_excerpt: str = ""
    local_artifact_paths: tuple[str, ...] = ()
    recommended_next_action: str = ""


@dataclass(frozen=True)
class BlockedRescuePlan:
    """Resolved branch/base/title for one blocked rescue PR."""

    branch: str
    base: str
    title: str


def blocked_branch(issue_number: int) -> str:
    """Branch name that preserves blocked code for ``issue_number``."""

    return f"ralph/issue-{issue_number}-blocked"


def blocked_pr_title(contract: IssueContract) -> str:
    """``Blocked: #<issue> <issue title>`` rescue-PR title."""

    return f"Blocked: #{contract.number} {contract.title}".strip()


def redact_secrets(text: str) -> str:
    """Redact values of secret-looking ``KEY=value`` assignments line by line.

    Only the *value* is replaced, so the surrounding log structure (and the key
    name, which is useful context) survives. Lines without a recognizable
    assignment are returned unchanged.
    """

    return "\n".join(_redact_line(line) for line in text.split("\n"))


def cap_excerpt(
    text: str,
    *,
    max_lines: int = MAX_EXCERPT_LINES,
    max_bytes: int = MAX_EXCERPT_BYTES,
) -> str:
    """Cap ``text`` by line count AND byte count, whichever bound is hit first.

    A truncation marker is appended when either bound trims content so reviewers
    know the published excerpt is partial and the full log stays local.
    """

    lines = text.split("\n")
    truncated = False
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        truncated = True
    capped = "\n".join(lines)
    encoded = capped.encode("utf-8")
    if len(encoded) > max_bytes:
        capped = encoded[:max_bytes].decode("utf-8", errors="ignore")
        truncated = True
    if truncated:
        capped = capped.rstrip("\n") + "\n[... truncated; full log kept locally ...]"
    return capped


class BlockedReportWriter:
    """Renders a :class:`BlockedReport` into a sanitized GitHub body/comment.

    Guarantees: never embeds full raw logs (excerpts are redacted and capped),
    never embeds ``Secrets.xcconfig`` content, and always references the issue
    with ``Refs #<issue>`` rather than any closing keyword.
    """

    def render(self, report: BlockedReport) -> str:
        sections = [
            f"## Blocked: #{report.issue} {report.title}".rstrip(),
            "",
            f"Refs #{report.issue}",
            "",
            self._summary_block(report),
        ]
        excerpt = self._excerpt_block(report)
        if excerpt:
            sections += ["", excerpt]
        sections += ["", self._artifacts_block(report)]
        if report.recommended_next_action:
            sections += [
                "",
                "### Recommended next action",
                "",
                report.recommended_next_action,
            ]
        return "\n".join(sections).rstrip() + "\n"

    def _summary_block(self, report: BlockedReport) -> str:
        prd = f"#{report.prd_number}" if report.prd_number is not None else "none"
        exit_status = "n/a" if report.exit_status is None else str(report.exit_status)
        repair = "yes" if report.repair_attempted else "no"
        rows = [
            "### Summary",
            "",
            f"- Issue: #{report.issue}",
            f"- PRD: {prd}",
            f"- Intended branch: `{report.intended_branch}`",
            f"- Failed phase/gate: {report.failed_phase_or_gate}",
            f"- Failing command: `{redact_secrets(report.failing_command)}`",
            f"- Exit status: {exit_status}",
            f"- Repair attempted: {repair}",
        ]
        if report.repair_attempted:
            rows.append(f"- Repair result: {report.repair_result or 'unknown'}")
        if report.changed_files:
            rows.append("- Changed files:")
            rows += [f"  - `{path}`" for path in report.changed_files]
        if report.diffstat:
            rows += ["", "### Diffstat", "", "```", report.diffstat.rstrip("\n"), "```"]
        return "\n".join(rows)

    def _excerpt_block(self, report: BlockedReport) -> str:
        if not report.sanitized_excerpt:
            return ""
        safe = cap_excerpt(redact_secrets(report.sanitized_excerpt))
        return "\n".join(["### Sanitized excerpt", "", "```", safe, "```"])

    def _artifacts_block(self, report: BlockedReport) -> str:
        if not report.local_artifact_paths:
            return "### Local artifacts\n\nNone recorded. Full logs stay local."
        rows = [
            "### Local artifacts",
            "",
            "Full logs are kept locally and gitignored (never uploaded):",
            "",
        ]
        rows += [f"- `{path}`" for path in report.local_artifact_paths]
        return "\n".join(rows)


class BlockedRescuePublisher:
    """Commits, pushes, and opens the draft rescue PR for blocked code.

    Mirrors the success publisher's commit/push/create-draft structure but uses
    ``Refs #<issue>`` (never a closing keyword) and never marks the PR ready. A
    PRD-scoped issue rescues onto the PRD stack branch when that branch already
    has an open PR; otherwise it bases on ``main``.
    """

    def __init__(self, client: GitHubClient, runner: GitRunner) -> None:
        self._client = client
        self._runner = runner
        self._writer = BlockedReportWriter()

    def plan(self, contract: IssueContract) -> BlockedRescuePlan:
        return BlockedRescuePlan(
            branch=blocked_branch(contract.number),
            base=self._base_branch(contract),
            title=blocked_pr_title(contract),
        )

    def publish(self, contract: IssueContract, report: BlockedReport) -> int:
        """Preserve blocked code in a draft rescue PR and flag the issue.

        Returns the rescue PR number. Commits and force-pushes the blocked tree,
        creates the draft PR (reusing one already open for the branch), posts the
        sanitized report as an issue comment, and applies the blocked labels.
        """

        plan = self.plan(contract)
        body = self._writer.render(report)
        self._commit_and_push(contract.number, plan.branch)
        pr_number = self._create_or_reuse_pr(plan, body)
        self._client.comment_issue(contract.number, body)
        self._apply_blocked_labels(contract.number)
        return pr_number

    def _base_branch(self, contract: IssueContract) -> str:
        if contract.prd_number is None:
            return BASE_BRANCH
        prd_branch = f"{_PRD_BRANCH_PREFIX}{contract.prd_number}"
        if self._client.find_pr_by_head_branch(prd_branch) is not None:
            return prd_branch
        return BASE_BRANCH

    def _create_or_reuse_pr(self, plan: BlockedRescuePlan, body: str) -> int:
        existing = self._client.find_pr_by_head_branch(plan.branch)
        if existing is not None:
            return _pr_number(existing)
        pr_number = self._client.create_pr(
            draft=True,
            base=plan.base,
            head=plan.branch,
            title=plan.title,
            body=body,
        )
        self._client.add_pr_labels(pr_number, [LABEL_AGENT_BLOCKED])
        return pr_number

    def _apply_blocked_labels(self, issue_number: int) -> None:
        self._client.remove_issue_labels(issue_number, [LABEL_READY_FOR_AGENT])
        self._client.add_issue_labels(issue_number, [LABEL_READY_FOR_HUMAN, LABEL_AGENT_BLOCKED])

    def _commit_and_push(self, issue_number: int, branch: str) -> None:
        message = blocked_commit_message(issue_number)
        self._run(["commit", "--allow-empty", "-m", message], "commit blocked tree")
        self._run(["push", "--force-with-lease", "origin", branch], f"push {branch}")

    def _run(self, args: Sequence[str], what: str) -> None:
        result = self._runner(list(args))
        if not result.ok:
            detail = result.stderr.strip() or result.stdout.strip()
            raise PublishError(f"failed to {what} (git exit {result.returncode}): {detail}")


def blocked_commit_message(issue_number: int) -> str:
    """Commit message for the preserved blocked tree.

    Uses ``Refs #<issue>`` (never a closing keyword) so merging the rescue PR
    does not auto-close the issue, which still needs human attention.
    """

    subject = f"wip: preserve blocked work for issue #{issue_number}"
    return f"{subject}\n\nRefs #{issue_number}\n"


def _redact_line(line: str) -> str:
    match = _ASSIGNMENT.match(line)
    if match is None:
        return line
    if not _should_redact(match.group("key")):
        return line
    return f"{match.group('indent')}{match.group('key')}{match.group('sep')}{REDACTION_PLACEHOLDER}"


def _should_redact(key: str) -> bool:
    upper = key.upper()
    if any(upper.startswith(prefix) for prefix in _REDACT_KEY_PREFIXES):
        return True
    return any(fragment in upper for fragment in _REDACT_KEY_FRAGMENTS)


def _pr_number(pr: dict) -> int:
    number = pr.get("number")
    if isinstance(number, bool) or not isinstance(number, int):
        raise PublishError(f"PR is missing an integer number: {pr!r}")
    return number
