# Ralph Review Phase Spec

## Goal

Rename Ralph's current `swift-review` phase to the broader `review` phase and
make that phase responsible for two independent review lenses: Swift code review
and spec conformance review.

The change exists because correct autonomous work needs both kinds of feedback.
`swift-reviewer` checks whether the implementation is technically sound. In the
Ralph review phase, `spec-conformance-reviewer` checks whether the
implementation satisfies the frozen GitHub issue contract and does not expand
beyond it.

## Background

Ralph already runs issue work through isolated phases in a deterministic Python
orchestrator. The current sequence is `implement-tdd`, `swift-review`,
`ui-verify`, then deterministic gates. The phase prompt
`ralph/prompts/swift-review.md` invokes `swift-reviewer` as a separate subagent,
fixes blocking findings in the worktree, commits remediation, and completes only
after the reviewer is clean.

Relevant docs:

- [Ralph Python PR Orchestrator Spec](2026-06-05-ralph-python-pr-orchestrator.md)
- [Ralph README](../../ralph/README.md)
- [Issue tracker conventions](../agents/issue-tracker.md)
- [Testing policy](../TESTING.md)

The orchestrator captures an immutable `IssueContract` before mutating agent
work. That contract is the durable authority for PRD membership, UI integration
test edit authority, issue body, labels, title, and context comments. Review
must use that frozen contract instead of live issue state.

## Decisions

- Decision: Rename the phase from `swift-review` to `review`.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: New Ralph runs emit `review` as the canonical phase name,
    prompt name, promise phase, log phase, and dashboard/report phase.

- Decision: Keep one review phase with two peer reviewer subagents.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: The pipeline stays compact:
    `implement-tdd -> review -> ui-verify -> gates`.

- Decision: Reviewer subagents are read-only.
  - Source: architecture discussion, 2026-06-05.
  - Consequence: `swift-reviewer` and `spec-conformance-reviewer` report
    blocking findings, but the phase agent is the only mutating actor.

- Decision: Spec conformance uses the frozen `IssueContract`.
  - Source: existing Ralph issue-contract model and architecture discussion,
    2026-06-05.
  - Consequence: The reviewer uses the captured Agent Brief when one exists;
    otherwise it uses the captured issue-body acceptance criteria. Related PRDs
    and specs are context only and cannot expand the issue contract.

- Decision: Review remediation follows the current Swift review loop.
  - Source: current `swift-review` prompt behavior.
  - Consequence: The phase agent fixes blocking findings, commits changes, and
    reruns the relevant reviewer or reviewers until both are clean.

## Scope

### In

- Rename the Ralph phase from `swift-review` to `review`.
- Replace the Swift-only review prompt with a review prompt that invokes both
  `swift-reviewer` and `spec-conformance-reviewer`.
- Define the `spec-conformance-reviewer` role and blocking standard.
- Create the `spec-conformance-reviewer` custom subagent definition.
- Update orchestrator phase sequencing, allowed actions, promise lines, logs,
  reports, dashboards, tests, and docs that own current phase vocabulary.
- Preserve historical report readability for existing `swift-review` artifacts.

### Out

- Changing the implementation phase.
- Changing the UI verification phase.
- Changing deterministic gates.
- Allowing reviewer subagents to edit files directly.
- Expanding the issue contract from PRDs, linked specs, comments added after
  contract capture, or live GitHub rereads.
- Changing workout app product behavior.
- Updating `CONTEXT.md`; this is Ralph harness behavior, not domain glossary
  language.

## Current Architecture

`ralph/orchestrator/loop.py` owns the phase sequence. It currently runs:

```text
implement-tdd -> swift-review -> ui-verify
```

For each phase, the orchestrator writes progressive-disclosure context through
`PromptContextWriter`, references the frozen `issue-contract.md`, builds a phase
prompt from `ralph/prompts/<phase>.md`, and sends a `PhaseRequest` to the
selected engine. The engine returns a normalized `PhaseResult`.

`ralph/prompts/swift-review.md` currently instructs the phase agent to spawn
`swift-reviewer`, fix blocking non-UI findings, commit remediation, and avoid UI
tests.

Reporting surfaces also know the current phase name:

- `ralph/report.py` parses activity and logs into phase attempts.
- `ralph/dashboard.py` abbreviates `swift-review` as `rev` and orders it before
  `ui-verify`.
- Existing generated reports may contain historical `swift-review` rows.

## Target Architecture

The orchestrator runs:

```text
implement-tdd -> review -> ui-verify
```

`review` is a single phase turn. Inside that phase, the phase agent spawns two
independent read-only reviewer subagents against the same frozen
`IssueContract` and the current `ISSUE_BASE_REF..HEAD` diff:

- `swift-reviewer`: reviews Swift correctness, maintainability, architecture
  fit, and non-UI test fit.
- `spec-conformance-reviewer`: reviews only conformance to the supplied spec.

The `spec-conformance-reviewer` custom subagent is installed beside the existing
global reviewer agents and is read-only. The subagent itself is generic enough
to review any caller-supplied spec, issue contract, acceptance criteria, brief,
diff, PR, repair patch, document, or generated artifact. Ralph's `review.md`
prompt supplies the Ralph-specific workflow context: the frozen `IssueContract`,
the current diff scope, the authority order, and the exact pass/block
expectations. The subagent reports only pass/blocking spec conformance findings
and never edits files, commits, pushes, relabels, closes issues, or mutates PR
state.

The phase agent gathers both reviewer reports, fixes any blocking findings in
the worktree, runs the narrowest relevant non-UI checks needed to prove fixes,
commits remediation, and reruns the relevant reviewer or reviewers. The phase
completes only when both reviewers report no blocking findings on the current
state.

When invoked by Ralph, the spec conformance reviewer treats PRDs, linked specs,
ADRs, comments, and docs as context. They may explain terms or intent, but they
do not override or expand the captured issue contract.

## Contracts

### Phase sequence [CHANGED]

New canonical sequence:

```text
implement-tdd -> review -> ui-verify
```

`swift-review` is no longer emitted by new normal Ralph runs.

### Review phase name [CHANGED]

The review phase uses:

```text
phase = "review"
prompt = "review.md"
complete promise = <promise phase="review">COMPLETE</promise>
blocked promise prefix = <promise phase="review">BLOCKED:
```

Historical `swift-review` phase names remain valid only for old reports and
existing artifacts.

### Reviewer roles [ADDED]

```text
ReviewerRole
  name: "swift-reviewer" | "spec-conformance-reviewer"
  mode: read-only
  input:
    - frozen IssueContract
    - ISSUE_BASE_REF..HEAD diff
    - relevant local docs opened only as needed
  output:
    - blocking findings
    - non-blocking observations, if useful
    - final pass/fail statement
```

`swift-reviewer` blocking findings are code-quality or technical correctness
findings that make the issue unsafe to publish.

`spec-conformance-reviewer` blocking findings are limited to:

- an unmet captured acceptance criterion
- missing required evidence or test coverage named by the issue contract
- behavior that satisfies adjacent PRD/spec context but not the child issue
- behavior or scope added beyond the captured issue contract
- a contradiction between implementation and the captured Agent Brief or issue
  body

Non-blocking suggestions must not prevent phase completion.

### Review phase remediation [CHANGED]

The phase agent is the only actor allowed to edit files. Reviewer subagents do
not mutate the worktree.

The review phase may:

- inspect the issue diff
- spawn `swift-reviewer`
- spawn `spec-conformance-reviewer`
- fix blocking non-UI findings
- run narrow non-UI checks needed to prove fixes
- commit review remediation

The review phase must not:

- run Xcode UI integration tests
- push, merge, open a PR, close a PR, or close the issue
- edit `ralph/*.sh`, `ralph/orchestrator/**`, or `ralph/prompts/**` while
  reviewing an ordinary app issue

### Review completion gate [CHANGED]

The review phase emits COMPLETE only when:

- `swift-reviewer` was invoked as a separate read-only subagent
- `spec-conformance-reviewer` was invoked as a separate read-only subagent
- both reviewers report no blocking findings on the current state
- every blocking finding from either reviewer was fixed and re-reviewed
- any files changed by the phase were committed
- no UI tests, screenshots, or UI screenshot review ran in this phase

If any condition fails, the phase emits the review phase BLOCKED promise.

### Historical phase compatibility [ADDED]

Report and dashboard readers should continue to display historical
`swift-review` activity. New reports should order and label phases as:

```text
select, implement, implement-tdd, review, ui-verify
```

Historical `swift-review` rows may be displayed as `swift-review (legacy)` or
kept as their raw phase name. They must not be rewritten in stored artifacts.

### Old Swift review phase [REMOVED]

`swift-review` as a canonical phase for new Ralph runs is removed. Its behavior
is subsumed by the new `review` phase.

## Migration Plan

### Phase 1: Review Contract and Prompt

- Change: Introduce `review.md` as the canonical prompt and define both reviewer
  responsibilities in that prompt.
- Compatibility: Keep the existing Swift review behavior inside the new review
  phase while adding spec conformance review.
- Acceptance criteria: The prompt requires both reviewer subagents, read-only
  review, phase-agent remediation, commits for phase edits, and the new review
  promise line.

### Phase 2: Orchestrator Phase Rename

- Change: Replace the normal phase constant and loop sequence from
  `swift-review` to `review`.
- Compatibility: `PhaseResult.phase` remains a string, so engine adapters do not
  need a shape change.
- Acceptance criteria: The orchestrator runs `implement-tdd`, then `review`,
  then `ui-verify`; blocked review results preserve code through the existing
  blocked path.

### Phase 3: Reporting and Documentation

- Change: Update Ralph README, architecture docs/spec references, report labels,
  dashboard labels, and tests that hard-code `swift-review`.
- Compatibility: Historical `swift-review` report rows remain readable.
- Acceptance criteria: New reports display `review`; old report data containing
  `swift-review` still renders without failure.

### Phase 4: Verification

- Change: Add or update tests for phase order, allowed actions, promise parsing,
  prompt context, report/dashboard ordering, and blocked review behavior.
- Compatibility: Existing fake-engine and CLI/SDK engine contracts continue to
  use the same `PhaseResult` shape.
- Acceptance criteria: Ralph orchestrator tests pass, report/dashboard tests pass,
  and a fake-engine run can complete with the new `review` phase.

## Deletion Criteria

- `ralph/prompts/swift-review.md` can be deleted after `review.md` is the only
  prompt referenced by normal orchestration and tests.
- `PHASE_SWIFT_REVIEW` can be deleted after all normal orchestration and repair
  references are renamed to review terminology.
- Dashboard/report special handling for current-run `swift-review` can be
  removed after no active Ralph workflow emits that phase name. Historical
  rendering support may remain indefinitely because stored reports are archival.

## Acceptance Criteria

- [ ] New Ralph issue runs emit `review`, not `swift-review`, between
  `implement-tdd` and `ui-verify`.
- [ ] The review prompt requires both `swift-reviewer` and
  `spec-conformance-reviewer` as separate read-only subagents.
- [ ] The review phase completes only when both reviewers are clean on the
  current worktree state.
- [ ] Blocking findings from either reviewer are remediated by the phase agent,
  committed, and re-reviewed.
- [ ] Spec conformance findings are limited to the frozen `IssueContract`; PRDs,
  linked specs, and live issue rereads do not expand scope.
- [ ] UI tests remain exclusive to later UI verification.
- [ ] Existing reports or dashboards containing historical `swift-review` data
  still render.

## Testing Strategy

Use Ralph's Python tests for orchestrator behavior and report/dashboard behavior.
Coverage should include the normal phase sequence, review phase allowed actions,
blocked review phase publication behavior, prompt context rendering, and
dashboard/report handling for both new `review` and historical `swift-review`
phase names.

Use a fake-engine run or equivalent test seam to prove the new phase name flows
through `PhaseRequest`, promise parsing, `PhaseResult`, logs, and publishing
without invoking real agents.

## Open Questions

- None.
