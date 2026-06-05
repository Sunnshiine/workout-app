# Ralph Python PR Orchestrator Spec

## Implementation Status

As of issue #214, `ralph/ralph.sh` is a thin compatibility wrapper around
`python -m ralph.orchestrator`. Direct-to-main publishing remains removed, live fake-engine
GitHub dry-run evidence is recorded under `docs/ralph/live-dry-runs/`, and the normal Python
issue-processing loop polls `origin/main` before selecting each eligible `ready-for-agent` issue.

## Goal

Replace Ralph's shell-owned orchestration with a Python state machine that ships autonomous work only through pull requests. The new orchestrator keeps the existing `ralph/ralph.sh` runner in production until the Python path has local tests plus a live dry-run proving GitHub wiring.

The change exists because Ralph has outgrown a linear shell script: PRD stacking, one-time UI repair, blocked rescue PRs, UI-test edit authority, sanitized failure reports, SDK-backed engines, and progressive-disclosure prompts all require explicit state and testable contracts.

## Background

Ralph currently lives primarily in `ralph/ralph.sh`. It selects one `ready-for-agent` GitHub issue, creates issue and integration worktrees, runs implementation/review/UI phases through Claude Code or Codex CLI, gates the integrated tree, then ships to a resolved target. The current README still describes direct-to-`main` as the normal path and existing PR branch routing as an exception.

The target behavior reverses that default: Ralph must never push or merge directly to `main`. All successful work lands on a draft or ready PR branch. PRD-tied issues stack on one PR; one-off issues get one PR. Blocked work that produced code is preserved as a separate draft rescue PR instead of being lost.

Bug issues need one extra guardrail before implementation. A bug fix should start from a
reproduced failure and a defensible fix plan, not from a plausible code guess. Ralph therefore adds
a diagnosis phase for issues labelled `bug`. That phase uses the repository's diagnosis discipline
to establish a feedback loop, decide whether UI integration coverage is required, and hand a local
diagnosis artifact to implementation.

Relevant existing docs:

- [Ralph README](../../ralph/README.md)
- [Testing policy](../TESTING.md)
- [Issue tracker conventions](../agents/issue-tracker.md)
- [Triage labels](../agents/triage-labels.md)
- [ADR 0007: Visual Regression Testing](../adr/0007-visual-regression-testing.md)

## Decisions

- Decision: Ralph becomes a Python orchestrator with SDK-backed engine adapters.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: Python owns deterministic workflow state; Codex/Claude only own agent turns.

- Decision: `ralph/ralph.sh` is not replaced until the Python path is implemented and fully tested.
  - Source: user direction, 2026-06-05.
  - Consequence: migration is side-by-side; the shell runner remains the production path until deletion criteria are met.

- Decision: Ralph must not publish directly to `main`.
  - Source: user direction, 2026-06-05.
  - Consequence: direct main merge, direct main push, and direct issue-close-on-main are removed from the target workflow.

- Decision: PRD membership is explicit.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: a child implementation issue is PRD-scoped only when its issue body contains an explicit `PRD: #<number>` directive. Ralph does not infer PRD membership from vague links, comments, labels, or GitHub parent relationships.

- Decision: PR branches are deterministic.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: PRD stacks use `ralph/prd-<prd-number>`; one-off issues use `ralph/issue-<issue-number>`; blocked rescue branches use `ralph/issue-<issue-number>-blocked`.

- Decision: Successful agent work is implemented-but-unmerged until the PR merges.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: Ralph applies `agent-implemented`, removes `ready-for-agent`, leaves the issue open, and uses `Closes #<issue>` only in the successful integration commit message so GitHub closes the issue when the PR merges.

- Decision: PR readiness represents scoped completion.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: PRD PRs remain draft while any child issue for that PRD is not `agent-implemented`; after all scoped issues are implemented, Ralph marks the PR ready for review and labels it `agent-ready-for-review`. One-off PRs can become ready for review after their single issue passes.

- Decision: Code produced before a failed gate is preserved in a blocked rescue PR.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: blocked rescue PRs are draft, use `Refs #<issue>` instead of closing keywords, carry `agent-blocked`, and include a sanitized failure report.

- Decision: UI-owned failures get one repair cycle before blocked escalation.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: Ralph writes a repair brief, runs one fresh repair agent context, reruns Swift review when repair changes code/tests/project files, and then reruns the relevant UI/full gates once.

- Decision: UI integration test edit authority is mechanical.
  - Source: UI-test authority handoff and [issue tracker conventions](../agents/issue-tracker.md).
  - Consequence: `Tests/UI/**` changes are accepted only when the pre-agent issue body snapshot contains exactly `UI integration test edits: authorized`; the UI verification phase may never edit `Tests/UI/**`.

- Decision: Bug issues must be diagnosed before implementation.
  - Source: Ralph diagnosis-gate design discussion, 2026-06-05.
  - Consequence: If the selected issue's frozen labels include `bug`, Ralph runs a `diagnose` phase before `implement-tdd`. Non-bug issues keep the existing implementation-first flow.

- Decision: Diagnosis handoff, issue authority, and audit history live on separate surfaces.
  - Source: Ralph diagnosis-gate design discussion, 2026-06-05.
  - Consequence: The full diagnosis plan is a local Ralph artifact; the issue body remains the durable authority source; issue comments record state-machine events such as Ralph granting UI integration test authority.

- Decision: Ralph may autonomously grant UI integration test edit authority only during bug diagnosis.
  - Source: Ralph diagnosis-gate design discussion, 2026-06-05.
  - Consequence: A completed diagnosis may request UI-test authority with a structured boolean block. Ralph may then edit the issue body, comment the transition, recapture the issue contract, and continue. No other phase may edit the issue body for this authority.

- Decision: Failure reports published to GitHub must be sanitized.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: blocked PR bodies and comments contain structured summaries and redacted excerpts, never raw full logs or secret-bearing files.

- Decision: Prompts use progressive disclosure.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: Python writes compact context artifacts and passes paths plus summaries; agents open full logs, comments, PRDs, or docs only when needed.

## Scope

### In

- Side-by-side Python Ralph orchestrator.
- SDK-backed Codex and Claude engine adapters as the primary/default target, with CLI adapters kept only as temporary migration and diagnostic fallbacks.
- PR-only publish target resolution.
- PRD stack detection and branch naming.
- Successful issue lifecycle: `agent-implemented`, draft/ready PRs, integration commit closing keywords.
- Blocked issue lifecycle: rescue PR, `ready-for-human`, `agent-blocked`, sanitized report.
- One UI-owned repair cycle.
- UI integration test edit authority enforcement.
- Bug-only diagnosis phase and diagnosis-to-implementation handoff.
- Diagnosis-driven UI integration test authority upgrade for `Tests/UI/**`.
- Progressive-disclosure prompt artifacts.
- Local unit/integration tests plus one live dry-run path with a fake engine.
- Documentation updates for Ralph operation, issue conventions, labels, and testing policy.

### Out

- Removing `ralph/ralph.sh` before the Python path passes acceptance.
- Rewriting `ralph/report.py` or `ralph/dashboard.py`, except for compatibility with new activity terms if needed.
- Changing app product behavior.
- Changing the Testing layer taxonomy outside what Ralph needs to enforce.
- Creating product PRDs or issue breakdowns.
- Depending on a single provider SDK as the workflow owner.
- Publishing raw logs or secrets to GitHub.
- Autonomously authorizing project wiring, package, scheme, or Xcode project changes outside
  `Tests/UI/**`.

## Current Architecture

`ralph/ralph.sh` is now a thin compatibility wrapper around `python -m ralph.orchestrator`.
Python owns the normal issue-processing loop:

- Polls `origin/main` before each iteration.
- Selects an open `ready-for-agent` issue from GitHub using structured selector rules.
- Captures an immutable `IssueContract`.
- Resolves deterministic PR targets.
- Creates a branch worktree under `.claude/worktrees/`.
- Runs phase prompts from `ralph/prompts/` through an `Engine` adapter.
- Writes compact context artifacts under `ralph/.artifacts/context/`.
- Runs deterministic app gates and mechanical authority checks.
- Publishes successful work only through PR branches.
- Preserves blocked work in draft rescue PRs with sanitized reports.

The current loop already treats the `bug` label as selector priority, but it does not yet insert a
diagnosis phase or let diagnosis grant UI integration test authority before implementation.

## Target Architecture

Python Ralph owns a typed orchestration boundary:

- `IssueSelector`: chooses one issue from GitHub using the same eligibility rules.
- `IssueContract`: immutable pre-agent snapshot of issue body, labels, title, comments needed for implementation, PRD directive, and UI-test edit authorization.
- `TargetResolver`: maps each issue to a PR branch and PR base.
- `WorktreeManager`: creates, copies `Secrets.xcconfig`, cleans up, and preserves worktrees when needed.
- `Engine`: runs one phase prompt in one worktree and returns a structured phase result.
- `DiagnosisAuthority`: parses the diagnosis authority block, validates whether Ralph may grant
  UI-test authority, and performs at most one corrective diagnosis-format retry.
- `GateRunner`: runs deterministic gates and returns structured gate failures.
- `AuthorityGate`: checks Visual Baseline and UI integration test edit policies.
- `RepairCoordinator`: writes the repair brief and controls exactly one UI-owned repair cycle.
- `PullRequestPublisher`: creates, reuses, updates, marks ready, and labels PRs.
- `IssuePublisher`: applies/removes issue labels and writes comments.
- `BlockedReportWriter`: generates sanitized failure reports for rescue PRs.
- `PromptContextWriter`: writes progressive-disclosure context artifacts.

Engine adapters are isolated behind the same interface:

- Primary/default: `CodexSdkEngine`
- Primary/default: `ClaudeSdkEngine`
- Temporary migration/diagnostic fallback: `CodexCliEngine`
- Temporary migration/diagnostic fallback: `ClaudeCliEngine`
- `FakeEngine` for tests and dry-runs

The SDK or CLI only runs the agent turn. It does not select targets, decide lifecycle state, mutate labels, create PRs, run gates, or decide whether code is safe to publish.

For a selected bug issue, the target phase order is:

```text
diagnose -> implement-tdd -> swift-review -> ui-verify -> gates -> PR publish
```

For non-bug issues, the phase order remains:

```text
implement-tdd -> swift-review -> ui-verify -> gates -> PR publish
```

## Contracts

### Issue contract [ADDED]

Captured before any mutating agent phase starts. Later enforcement uses this snapshot, not live comments or issue state rereads.

```text
IssueContract
  number: int
  title: string
  body: string
  labels: set[string]
  comments_for_context: list[IssueComment]
  prd_number: int | None
  ui_test_edits_authorized: bool
```

Rules:

- `prd_number` is set only from an explicit `PRD: #<number>` directive in the issue body.
- `ui_test_edits_authorized` is true only when the issue body contains the exact line `UI integration test edits: authorized`.
- Authorization from comments, Agent Briefs, or later body edits is ignored for the current run.

### PR target [ADDED]

```text
PrTarget
  branch: string
  base: string
  prd_number: int | None
  issue_number: int
  existing_pr_number: int | None
```

Rules:

- PRD issue: `branch = ralph/prd-<prd_number>`.
- One-off issue: `branch = ralph/issue-<issue_number>`.
- New PR branches start from `origin/main`.
- Later PRD issues start from `origin/ralph/prd-<prd_number>` when it exists.
- PR base is `main`.
- Ralph never fast-forwards, merges, or pushes `main`.

### Phase result [CHANGED]

Shell promise-line parsing becomes a structured result owned by the engine adapter.

```text
PhaseResult
  phase: string
  status: complete | blocked | timeout | failed
  final_response: string
  log_path: path
  started_at: timestamp
  finished_at: timestamp
```

Compatibility:

- CLI fallback adapters may still parse existing promise lines.
- SDK adapters should return the same contract regardless of provider event shape.

### Diagnosis phase [ADDED]

The diagnosis phase runs only when the selected issue's pre-agent `IssueContract.labels` contains
`bug`.

Rules:

- The phase must explicitly use the diagnosis skill and follow the feedback-loop discipline:
  reproduce the bug, state falsifiable hypotheses, identify the likely cause, and produce a fix
  plan.
- The phase may temporarily edit files, create scratch tests, capture screenshots, add
  instrumentation, or build a local harness to reproduce the failure.
- The phase must not commit.
- The phase must not implement the production fix.
- Temporary investigative changes may remain uncommitted for implementation to adopt or replace,
  as long as no commit is made before Ralph processes diagnosis authority.
- `implement-tdd` must read the diagnosis handoff before editing.
- `swift-review` and `ui-verify` receive the diagnosis handoff as optional context.

### Diagnosis handoff artifact [ADDED]

Ralph writes the completed diagnosis response to:

```text
ralph/.artifacts/context/issue-<issue>/diagnosis.md
```

The artifact is the implementation handoff. It should include:

- repro loop or best available evidence
- observed symptom
- most likely cause
- proposed fix plan
- regression-test seam recommendation
- required diagnosis authority block

The handoff is referenced from later `phase-context.md` artifacts. It is mandatory context for
`implement-tdd`, and optional supporting context for `swift-review` and `ui-verify`.

### Diagnosis authority block [ADDED]

Every completed bug diagnosis must include exactly one authority block:

```text
<diagnosis-authority>
ui_integration_test_edits_required: true
scope: Tests/UI/WorkoutTrackerUITests.swift
reason: Critical real-control logging workflow per docs/TESTING.md; lower-level tests cannot prove the tap path reaches the visible state.
</diagnosis-authority>
```

When UI integration test edits are not required:

```text
<diagnosis-authority>
ui_integration_test_edits_required: false
scope:
reason:
</diagnosis-authority>
```

Rules:

- `ui_integration_test_edits_required` is boolean-only: `true` or `false`.
- When the value is `true`, `scope` is required and must name only paths under `Tests/UI/**`.
- When the value is `true`, `reason` is required and must explain why lower-level coverage is
  insufficient under [Testing policy](../TESTING.md).
- When the block is missing, malformed, or incomplete, Ralph runs one corrective diagnosis-format
  pass in the same worktree asking only for the corrected block from existing findings.
- If the corrective pass still cannot produce a valid block, Ralph escalates for human attention.
- Scope outside `Tests/UI/**` cannot be autonomously authorized by this mechanism.

### Diagnosis-driven UI authority upgrade [ADDED]

If diagnosis completes with `ui_integration_test_edits_required: true` and the current issue
contract is not already authorized:

1. Ralph reuses an existing `## Test authority` issue-body section or appends one if missing.
2. Ralph adds the exact line `UI integration test edits: authorized`.
3. Ralph records the diagnosis `scope` and `reason` in that section.
4. Ralph appends an issue comment recording the authority grant as a state-machine event.
5. Ralph recaptures `IssueContract` from GitHub.
6. Ralph proceeds to implementation only with the recaptured contract.

The issue body remains the authority source. The comment is an audit/event log. The local
`diagnosis.md` artifact remains the full implementation handoff.

Ralph may perform this issue-body edit only during the bug diagnosis transition. `implement-tdd`,
`swift-review`, `ui-verify`, repair phases, and gates may not edit the issue body to grant UI-test
authority.

If the issue body already contains `UI integration test edits: authorized`, Ralph does not duplicate
the body marker. It may still append a diagnosis comment when the diagnosis adds useful scope or
rationale, and it still recaptures the issue contract before implementation.

### Gate result [ADDED]

```text
GateResult
  name: string
  status: passed | failed | skipped
  command: list[string]
  exit_status: int | None
  log_path: path | None
  failure_excerpt: string | None
  ui_owned: bool
```

`ui_owned` is true for UI integration tests, UI screenshot artifact/review checks, Visual Regression failures, and Visual Baseline authority failures.

### Successful integration commit [CHANGED]

Successful issue commits on a PR branch include a closing keyword:

```text
merge: implement issue #<issue> via Ralph (<engine>)

Closes #<issue>
```

Ralph does not close the issue directly. GitHub closes it when the successful PR merges.

### Issue labels [CHANGED]

- `ready-for-agent`: issue is available for Ralph selection.
- `agent-implemented`: Ralph successfully pushed the issue implementation to a PR; issue remains open until PR merge.
- `ready-for-human`: issue needs human attention.
- `agent-blocked`: Ralph preserved blocked code or hit a policy failure; human must inspect.

On success:

- remove `ready-for-agent`
- add `agent-implemented`
- do not add `ready-for-human`
- do not close the issue

On blocked:

- remove `ready-for-agent`
- add `ready-for-human`
- add `agent-blocked`
- do not add `agent-implemented`
- do not close the issue

### Pull request lifecycle [ADDED]

Successful PRs:

- Created as draft when first pushed.
- Reused by branch on later pushes.
- One-off PR becomes ready for review after its issue passes.
- PRD PR becomes ready for review only when all known scoped child issues are `agent-implemented` and none are still `ready-for-agent`, `ready-for-human`, or `agent-blocked`.
- Ready PRs receive `agent-ready-for-review`.

Known scoped child issues for `PRD: #<n>` are the non-PRD GitHub issues whose current issue body
contains the exact `PRD: #<n>` directive. Ralph does not count the PRD issue itself, comments, or
future issues that have not yet been created. If a new child issue is added after the PR becomes
ready, the next Ralph run may move the PR back to draft before stacking more work.

Blocked rescue PRs:

- Branch: `ralph/issue-<issue>-blocked`.
- Title: `Blocked: #<issue> <issue title>`.
- Draft.
- Label: `agent-blocked`.
- Body uses `Refs #<issue>`, never `Closes #<issue>`.
- PRD blocked issue targets the PRD stack branch when that branch exists; otherwise it targets `main`.

### UI integration test edit authority [ADDED]

Authority gate:

- If `issue_base..issue_tip` changes `Tests/UI/**`, then `IssueContract.ui_test_edits_authorized` must be true.
- If `project.yml` or `WorkoutTracker.xcodeproj/project.pbxproj` changes UI test target wiring, `IssueContract.ui_test_edits_authorized` must be true.
- If `ui_phase_base..ui_phase_tip` changes `Tests/UI/**`, block unconditionally.

This is a parent-orchestrator gate. It must not depend on prompt compliance.

Diagnosis-driven authority grants are intentionally narrower than the gate. Ralph may
autonomously grant authority for `Tests/UI/**` changes only. If diagnosis finds that correct UI
coverage also requires `project.yml`, `Package.swift`, `WorkoutTracker.xcodeproj/project.pbxproj`,
scheme files, or other test-target wiring changes, Ralph must escalate for human authority instead
of granting that broader scope itself.

### UI repair cycle [ADDED]

For the first UI-owned gate failure after code exists:

1. Write `ralph/.artifacts/repair/issue-<issue>-ui-gate.md`.
2. Run one fresh `repair-ui-gate` agent context in the failing integration worktree.
3. If repair changes production Swift, test files, project files, or package configuration, run `swift-review-after-repair`.
4. Rerun the relevant UI/full gate once.
5. Ship on pass; create blocked rescue PR on second failure.

The repair prompt must say the agent is debugging the UI-owned failure and must stay inside the issue acceptance criteria. It must not weaken UI tests unless the issue contract authorizes test edits, and UI verification still may not edit `Tests/UI/**`.

### Progressive-disclosure prompt artifacts [ADDED]

Python writes small context files and prompts reference them by path:

- `issue-contract.md`
- `phase-context.md`
- `diagnosis.md`
- `gate-failure-summary.md`
- `repair-brief.md`
- `blocked-report.md`

Prompts always include role, issue, target, allowed actions, and completion/block contract. Full logs, PRD bodies, screenshots, issue comments, and prior phase transcripts are included by reference first and opened only when needed.

When `diagnosis.md` exists, the implementation prompt must require reading it before edits. Review
and UI verification prompts should receive it as supporting context for checking the implemented fix
against the diagnosed cause and the chosen regression seam.

### Sanitized blocked report [ADDED]

Blocked PR body/comment uses a structured sanitized report:

```text
BlockedReport
  issue
  title
  prd_number
  intended_branch
  failed_phase_or_gate
  failing_command
  exit_status
  repair_attempted
  repair_result
  changed_files
  diffstat
  sanitized_excerpt
  local_artifact_paths
  recommended_next_action
```

Rules:

- Never publish full raw logs.
- Never publish `Secrets.xcconfig`.
- Redact `*_TOKEN`, `*_SECRET`, `*_KEY`, `PASSWORD`, `OPENAI_API_KEY`, `CODEX_API_KEY`, `GH_TOKEN`, `GITHUB_TOKEN`, and `GOOGLE_*`.
- Cap excerpts by line count and byte count.
- Raw logs remain local and gitignored under `ralph/.artifacts/`.

### Removed direct-main publish path [REMOVED]

The target Python workflow has no direct `origin/main` push or local `main` fast-forward path. Any legacy `--publish-target main` option is invalid in the Python runner.

## Migration Plan

### Phase 1: Python Skeleton and Compatibility Adapters

- Change: Add a side-by-side Python package for Ralph orchestration with config parsing, structured logging, `Engine` adapters, `FakeEngine`, and a no-publish dry-run mode.
- Compatibility: `ralph/ralph.sh` remains unchanged and remains the production runner.
- Acceptance criteria:
  - Python entrypoint can run help/config validation without touching GitHub or agents.
  - Unit tests cover CLI/config parsing and fake-engine phase results.
  - No existing Ralph shell behavior changes.

### Phase 2: Routing, Issue Contract, and PR Target Resolution

- Change: Implement issue selection inputs, pre-agent issue snapshots, PRD directive parsing, UI-test authority parsing, deterministic branch naming, and PR lookup by branch.
- Compatibility: No agent execution required; can run against fixture JSON and fake GitHub clients.
- Acceptance criteria:
  - Tests cover PRD vs one-off routing, branch reuse, no direct main target, and UI-test marker capture from issue body only.

### Phase 3: Worktrees, Gates, and Authority Policies

- Change: Implement worktree management, `Secrets.xcconfig` copy behavior, deterministic gate results, Visual Baseline authority, and UI integration test edit authority.
- Compatibility: Existing shell runner still owns production execution.
- Acceptance criteria:
  - Tests cover unauthorized `Tests/UI/**` changes blocking, authorized implementation-phase UI-test edits passing, UI-verify UI-test edits blocking, and Visual Baseline authority statuses.

### Phase 4: Successful PR Publishing Lifecycle

- Change: Create/reuse draft PRs, push successful integration commits to PR branches, apply `agent-implemented`, update PR readiness, and use integration commit closing keywords.
- Compatibility: Use fake GitHub for local tests; live dry-run uses a fake engine and controlled test issue/branch.
- Acceptance criteria:
  - Tests cover successful one-off PR ready state and PRD PR draft-to-ready transition.
  - Live dry-run proves GitHub label/PR/comment wiring without letting a real agent edit code.

### Phase 5: UI Repair and Blocked Rescue PRs

- Change: Add one UI repair cycle, repair brief generation, `swift-review-after-repair`, blocked rescue PRs, `agent-blocked`, and sanitized blocked reports.
- Compatibility: Fake engine can force gate failures and repair outcomes.
- Acceptance criteria:
  - Tests cover first UI failure repair success, second UI failure blocked escalation, policy failure blocked escalation, no closing keywords on blocked PRs, and report redaction.

### Phase 6: SDK Engines and Progressive Prompts

- Change: Add `CodexSdkEngine` and `ClaudeSdkEngine` as intended/default adapters backed by `openai-codex` and `claude-agent-sdk`; keep CLI fallback adapters only for temporary migration and diagnostics. Convert phase prompts to progressive-disclosure artifacts.
- Compatibility: CLI fallback remains available until SDK auth, permissions, structured logs, and timeout behavior are proven locally.
- Acceptance criteria:
  - SDK smoke tests can run a harmless read-only phase in a fixture worktree.
  - Prompt artifacts are written and referenced instead of embedding full logs/comments by default.
  - Missing SDK packages degrade to explicit CLI fallback adapters; installed SDK packages are the default for `codex` and `claude`.

### Phase 6b: Bug Diagnosis and Authority Upgrade

- Change: Add the bug-only `diagnose` phase, local `diagnosis.md` handoff, authority-block parser,
  one corrective diagnosis-format retry, issue-body authority grant, audit comment, and contract
  recapture before implementation.
- Compatibility: Non-bug issues keep the current phase order. Bug issues without UI-test authority
  needs proceed through diagnosis and implementation without GitHub body edits.
- Acceptance criteria:
  - Tests cover bug issues running `diagnose` before `implement-tdd`.
  - Tests cover non-bug issues skipping diagnosis.
  - Tests cover completed diagnosis requiring a valid boolean authority block.
  - Tests cover one corrective retry for a missing or malformed authority block.
  - Tests cover Ralph reusing/appending `## Test authority`, adding an audit comment, and
    recapturing `IssueContract`.
  - Tests cover auto-authority being limited to `Tests/UI/**`.
  - Tests cover `diagnosis.md` being mandatory context for implementation and referenced for later
    phases.

### Phase 7: Replacement Gate

- Change: Replace `ralph/ralph.sh` with a thin compatibility wrapper only after all previous phases pass and the user approves the switch.
- Compatibility: Existing command shape should continue where practical; removed direct-main options must fail clearly.
- Acceptance criteria:
  - Local test suite passes.
  - Live dry-run passes.
  - One non-mutating or fake-engine end-to-end run is reviewed.
  - README and docs describe the Python runner as the canonical path.

## Deletion Criteria

- `ralph/ralph.sh` orchestration can be deleted or replaced with a wrapper only after the Python runner passes all local tests, the live dry-run, and explicit human approval.
- CLI fallback adapters should be removed after both SDK adapters prove stable with local auth, unattended permissions, structured logs, and timeout handling.
- Legacy direct-main docs/options can be removed once the Python runner is canonical and README no longer documents direct-main publishing.
- Any compatibility parser for old branch directives can be removed after open `ready-for-agent` issues have been migrated to the explicit PRD/PR-only directives.

## Acceptance Criteria

- [ ] Python Ralph exists side-by-side and does not alter `ralph/ralph.sh` production behavior before replacement approval.
- [ ] Python Ralph has no successful direct-to-main publish path.
- [ ] PRD issues stack on `ralph/prd-<n>` and one-off issues use `ralph/issue-<n>`.
- [ ] Successful issue work applies `agent-implemented`, removes `ready-for-agent`, leaves the issue open, and uses `Closes #<issue>` only in the successful integration commit.
- [ ] PRD PRs remain draft until all scoped child issues are `agent-implemented`; one-off PRs can become ready after their issue passes.
- [ ] Blocked code is preserved in a draft rescue PR with `Refs #<issue>`, `agent-blocked`, `ready-for-human`, and a sanitized blocked report.
- [ ] One UI-owned repair cycle runs before blocked escalation, and never loops indefinitely.
- [ ] Unauthorized UI integration test edits block mechanically.
- [ ] Bug-labelled issues run diagnosis before implementation.
- [ ] Completed bug diagnosis emits a boolean diagnosis authority block.
- [ ] Ralph can autonomously grant UI integration test edit authority only during diagnosis, only
      for `Tests/UI/**`, and only after recording the body update plus an audit comment.
- [ ] Ralph recaptures `IssueContract` after any diagnosis-driven issue-body authority update.
- [ ] `diagnosis.md` is mandatory context for implementation and available to later phases.
- [ ] UI verification phase edits to `Tests/UI/**` block unconditionally.
- [ ] Blocked reports redact secrets and never publish raw full logs.
- [ ] Prompt artifacts use progressive disclosure and avoid embedding full logs/comments unless required.
- [ ] Local tests cover routing, lifecycle labels, PR readiness, authority gates, repair retry, blocked PRs, and redaction.
- [ ] A live dry-run proves GitHub label/PR/comment wiring with a fake engine before replacing the shell runner.

## Testing Strategy

Use Python unit tests for pure routing and state transitions, with fake GitHub/Git/Engine dependencies. Use focused integration tests for worktree operations and gate result parsing against local fixture repositories. Use redaction tests with representative secret-looking log lines. Use fake-engine end-to-end tests to prove success, bug diagnosis, diagnosis authority upgrades, UI repair, policy escalation, and second-failure rescue PR paths without calling real agents.

Run one live dry-run against GitHub only after local tests pass. The live dry-run must use a fake engine and a controlled issue/branch so it proves `gh` authentication, label application, PR creation/update, comments, and draft/ready state handling without allowing autonomous code edits.

The Swift app test suite is not the primary test surface for the Python orchestrator, but the final replacement gate must prove the Python runner invokes the same documented app gates from [docs/TESTING.md](../TESTING.md).

## Open Questions

- None for the bug diagnosis and authority-upgrade workflow.
