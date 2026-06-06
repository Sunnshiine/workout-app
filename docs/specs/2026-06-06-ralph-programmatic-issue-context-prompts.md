# Ralph Programmatic Issue Context Prompts Spec

## Goal

Move Ralph's implementation-phase issue and comment discovery out of agent phase
prompts and into the Python orchestrator's programmatic context capture.
Implementation, review, UI verification, and repair agents should consume frozen
local context artifacts instead of spending agent tokens and tool calls on
`gh issue view <n> --comments`.

This keeps Ralph aligned with the existing PR-only Python orchestrator design:
Python owns GitHub reads, workflow state, authority, and prompt hydration; engines
own one bounded agent turn inside one worktree.

## Background

The [Ralph Python PR Orchestrator Spec](2026-06-05-ralph-python-pr-orchestrator.md)
already establishes progressive-disclosure prompts and an immutable
`IssueContract`. The [Ralph Review Phase Spec](2026-06-05-ralph-review-phase-spec-conformance.md)
already requires review to use the frozen `issue-contract.md` instead of live
GitHub state. The current implementation matches that direction in code:
`GhCliClient` fetches issue JSON, `IssueContract` normalizes the snapshot, and
`PromptContextWriter` writes local context artifacts.

The remaining gap is prompt-level drift. `implement.md` and `ui-verify.md` still
tell the agent to run `gh issue view <n> --comments`. That repeats a GitHub read
the orchestrator can perform once, burns agent tokens, risks sandbox/auth
failures inside the agent turn, and weakens the frozen-contract model by
inviting live rereads after claim. `diagnose.md` is intentionally exempt in V1:
bug diagnosis may still read the GitHub issue and comments before handing off to
implementation.

This spec also follows the prompt-structuring direction from Anthropic's Claude
prompting best practices: put role, context, instructions, and output contracts in
clearly separated sections, and supply context explicitly instead of relying on
the model to infer when to use tools.

Relevant docs:

- [Ralph Python PR Orchestrator Spec](2026-06-05-ralph-python-pr-orchestrator.md)
- [Ralph Review Phase Spec](2026-06-05-ralph-review-phase-spec-conformance.md)
- [Ralph README](../../ralph/README.md)
- [Issue tracker conventions](../agents/issue-tracker.md)
- [Testing policy](../TESTING.md)
- [PR #256: Ralph UI smoke gate planning](https://github.com/Sunnshiine/workout-app/pull/256)
- [Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)

## Decisions

- Decision: Post-diagnosis agents no longer run GitHub issue reads for contract discovery.
  - Source: architecture discussion, 2026-06-06.
  - Consequence: `implement-tdd`, `review`, `ui-verify`, and repair prompts use
    orchestrator-written context artifacts for issue body, comments, labels, PRD
    membership, blockers, and authority.

- Decision: Diagnosis may still read live GitHub issue context in V1.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: `diagnose.md` may keep `gh issue view <n> --comments` while the
    implementation handoff remains local and later phases use frozen context.

- Decision: Python remains the GitHub lifecycle owner during a Ralph run.
  - Source: [Ralph Python PR Orchestrator Spec](2026-06-05-ralph-python-pr-orchestrator.md).
  - Consequence: Python remains the owner of lifecycle reads/writes and
    post-diagnosis contract hydration. The V1 diagnosis prompt may still read
    issue/comments live, but prompt compliance is not used as an authority
    boundary.

- Decision: The issue body is the only implementation-contract authority.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: Comments, including comments labelled `Agent Brief`, may provide
    context or handoff notes, but they do not override the issue body.

- Decision: Full comments remain available as post-diagnosis context, but not as
  live tool calls.
  - Source: progressive-disclosure prompt design.
  - Consequence: The prompt points to a local `issue-comments.md` artifact when
    comments are useful. Comments can clarify context, but authority comes from
    the issue body.

- Decision: Comments are split out of the issue contract artifact.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: `issue-contract.md` stays short and authority-focused;
    `issue-comments.md` carries optional context-only comments.

- Decision: Prompt preambles use structured sections instead of flat key/value
  text.
  - Source: Claude prompt best practices and current prompt ambiguity.
  - Consequence: The XML-style Ralph phase envelope is required in this spec,
    separating runtime data, authority, allowed actions, forbidden actions,
    reference paths, and completion contracts.

- Decision: XML is used only for the model-facing prompt envelope.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: Local context artifacts remain markdown so issue bodies,
    comments, code blocks, and handoff notes stay human-readable.

- Decision: Phase action labels follow the PR #256 UI testing split.
  - Source: [PR #256](https://github.com/Sunnshiine/workout-app/pull/256).
  - Consequence: Prompts distinguish Visual Regression tests, UI Integration
    Smoke, and the UI Interaction Suite instead of using the broad phrase "UI
    tests".

- Decision: Every phase prompt envelope includes forbidden actions.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: The XML wrapper makes phase boundaries explicit instead of
    relying only on allowed actions or prose in the phase prompt body.

- Decision: UI verification remains read-only.
  - Source: current UI verification policy and mechanical authority gate.
  - Consequence: Any prompt-context contract that lists UI verification actions
    must not include code edits or commits for `ui-verify`.

## Scope

### In

- Programmatic capture and rendering of the issue body, labels, comments, PRD
  directive, blockers, and UI-test edit authority before agent phases.
- Removal of `gh issue view <n> --comments` instructions used for contract
  discovery from implementation, review, UI verification, and repair prompts.
- Structured prompt envelope for Ralph phase prompts.
- Explicit prompt-context contracts for `diagnose`, `implement-tdd`, `review`,
  `ui-verify`, and repair/review-after-repair prompts.
- Tests that prove post-diagnosis phase prompts rely on local context artifacts
  and do not ask agents to run GitHub issue reads for contract discovery.
- Fixing the current `ui-verify` allowed-actions contradiction.

### Out

- Changing Ralph's PR-only publication lifecycle.
- Changing selector behavior that uses GitHub before issue claim.
- Removing `gh` from the orchestrator itself.
- Removing diagnosis's V1 live issue/comment read.
- Adding machine-readable JSON context artifacts.
- Updating operator docs such as `ralph/README.md` or
  `docs/agents/issue-tracker.md`.
- Changing app product behavior.
- Changing the Testing layer taxonomy.
- Publishing issues or creating a product PRD.
- Removing SDK or CLI engine adapters.

## Current Architecture

`ralph/orchestrator/github.py` owns the `GitHubClient` seam. The production
`GhCliClient` already runs:

```text
gh issue view <issue> --json number,title,body,labels,comments,state
```

The orchestrator claims an issue, captures an `IssueContract`, resolves a PR
target, creates a worktree, and writes context artifacts under:

```text
ralph/.artifacts/context/issue-<issue>/
```

Current artifacts include:

- `issue-contract.md`
- `phase-context.md`
- `diagnosis.md`
- `gate-failure-summary.md`
- `repair-brief.md`
- `blocked-report.md`

The current `issue-contract.md` includes title, body, labels, PRD membership,
UI-test authority, and comments for context. Current prompts still ask agents to
treat `Agent Brief` comments as authoritative; the target model removes that
comment-authority path and moves captured comments to a separate artifact.

Current prompt gaps:

- `implement.md` tells the agent to read the issue and comments through `gh`.
- `ui-verify.md` tells the agent to re-read the issue and comments through `gh`.
- `review.md` already uses `CONTEXT_PATH` and the frozen `issue-contract.md`.
- `_allowed_actions_for_phase("ui-verify")` currently includes `commit UI fixes`
  even though the UI verification prompt says the phase is read-only.

## Target Architecture

The orchestrator hydrates issue-tracker context and writes local context paths
before phase prompts. Post-diagnosis agents may read files in the worktree and
local context artifacts, but they should not run GitHub issue or PR reads to
understand the contract.

Target ownership:

- `GitHubClient`: fetches GitHub issue/PR data and performs lifecycle mutations.
- `IssueContract`: immutable issue authority snapshot.
- `PromptContextWriter`: renders human-readable markdown context artifacts from
  the snapshot.
- `PhaseContext`: names the phase, role, target, allowed actions, forbidden
  actions, reference paths, and completion contract.
- Phase prompts: describe phase behavior against local context; post-diagnosis
  prompts do not discover issue state.
- Engine adapters: run one phase prompt; they do not own GitHub discovery.

Target phase prompt shape:

```xml
<ralph_phase>
  <runtime>
    <engine>codex</engine>
    <phase>implement-tdd</phase>
    <issue>225</issue>
    <worktree>/path/to/.claude/worktrees/issue-225</worktree>
    <issue_base_ref>...</issue_base_ref>
    <target_branch>ralph/issue-225</target_branch>
    <publish_target>pr</publish_target>
  </runtime>
  <authority>
    <context_path>ralph/.artifacts/context/issue-225/phase-context.md</context_path>
    <issue_contract_path>ralph/.artifacts/context/issue-225/issue-contract.md</issue_contract_path>
    <diagnosis_path></diagnosis_path>
  </authority>
  <allowed_actions>...</allowed_actions>
  <forbidden_actions>...</forbidden_actions>
  <reference_paths>...</reference_paths>
  <completion_contract>...</completion_contract>
  <phase_instructions>...</phase_instructions>
</ralph_phase>
```

The XML-style envelope is not a new parser requirement for provider output and
does not require XML context artifacts. It is a prompt construction contract for
clarity and consistency.

## Contracts

### Post-diagnosis GitHub issue read owner [CHANGED]

Only the orchestrator performs GitHub issue reads for post-diagnosis Ralph phase
context.

Rules:

- Selector may read GitHub to choose a candidate.
- Claim may fresh-read GitHub to ensure lifecycle labels converge.
- Contract capture may read GitHub to build the frozen snapshot.
- Implementation, review, UI verification, and repair agents must not be
  instructed to run `gh issue view`, `gh issue list`, or `gh pr view` to
  understand the issue contract.
- Diagnosis is exempt in V1 and may read the issue/comments live.
- GitHub writes remain orchestrator-owned lifecycle transitions.

### Issue contract [CHANGED]

`IssueContract` remains the immutable issue snapshot, but its rendered contract
must distinguish authority fields from context fields.

```text
IssueContract
  number: int
  title: string
  body: string
  labels: set[string]
  comments_for_context: list[IssueComment]
  prd_number: int | None
  ui_test_edits_authorized: bool
  blocked_by: list[int]
```

Rules:

- `prd_number`, `ui_test_edits_authorized`, and `blocked_by` continue to come
  from issue body parsing only.
- The issue body is the implementation contract for phase agents.
- Comments are context only, even when they contain an `Agent Brief` marker.
- If the issue body is too vague for the phase to complete safely, the phase
  reports BLOCKED instead of using comments as substitute authority.

### Vague issue body handling [ADDED]

Ralph does not add a mechanical body-shape gate in V1.

Rules:

- The selector may continue using the current lightweight eligibility check.
- The phase agent reads the frozen body as authority.
- Comments may clarify, but they do not replace or override the body.
- When the body is too vague to implement or verify safely, the phase reports
  BLOCKED with the phase-specific promise line.

### Issue comments artifact [ADDED]

Full captured comments are written to a local artifact when present:

```text
ralph/.artifacts/context/issue-<issue>/issue-comments.md
```

Rules:

- The artifact contains captured comments only; it does not fetch live comments.
- It is referenced from `phase-context.md`.
- It may be opened by agents when context is needed.
- It is not an authority source.
- `issue-contract.md` should not embed full comment bodies.
- The artifact format remains markdown.

### Phase context [CHANGED]

`PhaseContext` gains explicit forbidden actions and structured reference paths.

```text
PhaseContext
  role: string
  phase: string
  target_branch: string
  existing_pr_number: int | None
  complete_promise_line: string
  blocked_promise_prefix: string
  allowed_actions: list[string]
  forbidden_actions: list[string]
  reference_paths: list[ContextReference]
```

```text
ContextReference
  path: string
  kind: issue_contract | comments | diagnosis | gate_failure | repair_brief | blocked_report | log | screenshot | doc
  required: bool
  authority: bool
```

Rules:

- `issue-contract.md` is always required and authority-bearing.
- `diagnosis.md` is required for `implement-tdd` when present and context-only
  for review/UI verification.
- `issue-comments.md` is optional context and never authority.
- Logs and screenshots are reference-only and opened only when needed.

### Phase prompt envelope [ADDED]

Ralph builds a structured prompt envelope around each existing phase prompt.

Rules:

- Runtime values are grouped under `<runtime>`.
- Authority files are grouped under `<authority>`.
- Allowed and forbidden actions are explicit for every phase.
- Completion and blocked promise lines are grouped under
  `<completion_contract>`.
- The phase prompt body is grouped under `<phase_instructions>`.
- The envelope must not include blank key/value lines for missing optional paths;
  absent optional values should render as empty XML elements or omitted fields.
- Referenced context artifacts remain markdown files, not XML documents.

### Phase prompt GitHub command removal [REMOVED]

The following prompt instructions are removed from implementation, review, UI
verification, and repair prompts:

```text
Read the issue and comments: `gh issue view <n> --comments`.
Re-read the issue and comments: `gh issue view <n> --comments`.
```

Replacement rule:

```text
Read CONTEXT_PATH first. The frozen issue contract is rendered there or
referenced by local path. Captured comments, when present, are referenced through
`issue-comments.md`. Do not run GitHub issue commands to discover the contract.
Do not treat comments as contract authority.
```

### Implementation verification boundary [ADDED]

`implement-tdd` may run the narrowest relevant checks for the layer being
changed, including Visual Regression tests when a change affects covered visual
surfaces.

`implement-tdd` forbidden actions include:

```text
- run the full Xcode UI integration target
- run the full WorkoutTrackerUITests bundle
- run UI Interaction Suite tests
- spawn review subagents
- push, merge, open PRs, close PRs, or close issues
```

Rules:

- Do not use the phrase "do not run UI tests" for this boundary; it is too
  broad.
- Visual Regression tests are the deterministic visual gate and may run during
  implementation when applicable.
- Visual Regression tests compare rendered pixels to committed Visual Baseline
  PNGs programmatically; they are not AI screenshot review.
- UI Integration Smoke is the Ralph-owned real-control wiring gate and belongs
  to `ui-verify`.
- UI Interaction Suite tests are broader/higher-flake checks and remain outside
  normal Ralph phase execution.

### UI verify allowed actions [CHANGED]

`ui-verify` allowed actions are:

```text
- run UI Integration Smoke class-level selectors
- write review artifacts under ralph/.artifacts/
```

`ui-verify` forbidden actions include:

```text
- edit code
- edit Tests/UI/**
- commit changes
- spawn review subagents
- run the full `WorkoutTrackerUITests` bundle
- run UI Interaction Suite tests
- push, merge, open PRs, close PRs, or close issues
```

Rules:

- `ui-verify` runs smoke-only XCUI selectors, not the full UI target.
- Acceptable selector shape:
  `-only-testing:WorkoutTrackerUITests/<SmokeTestClass>`.
- The prompt must not ask for `-only-testing:WorkoutTrackerUITests`.

### Selector GitHub reads [CHANGED]

The no-agent-GitHub-read-for-contract-discovery rule applies to post-diagnosis
implementation, review, UI verification, and repair phases. Selection and claim
remain orchestrator-owned GitHub operations. Diagnosis is exempt in V1.

Rules:

- Normal Python selection uses the `GitHubClient` seam before phase prompts run.
- Any diagnostic selector prompt, if retained, may inspect GitHub before claim but
  must not be reused as a mutating phase prompt.
- Once a post-diagnosis phase prompt starts, issue contract discovery comes from
  local context artifacts only.

## Migration Plan

### Phase 1: Context Contract Expansion

- Change: Extend issue context rendering so the issue body is clearly labelled
  as authority and captured comments are split into a context-only local
  artifact.
- Compatibility: Existing `IssueContract` fields keep their current meanings.
- Acceptance criteria:
  - `issue-contract.md` identifies the issue body as the implementation
    authority.
  - `issue-comments.md` is written when comments exist.
  - `issue-contract.md` does not embed full comment bodies.
  - Tests cover no comments, ordinary comments, and comments containing
    `Agent Brief` markers that remain context only.

### Phase 2: Structured Prompt Envelope

- Change: Replace the flat phase preamble with the required XML-style Ralph
  phase envelope.
- Compatibility: Existing phase prompt files remain markdown bodies under
  `<phase_instructions>`.
- Acceptance criteria:
  - Every normal phase prompt is wrapped in `<ralph_phase>`.
  - Prompt-rendering tests assert runtime, authority, allowed actions, forbidden
    actions, references, and completion contract are separated.
  - Missing optional diagnosis paths do not render confusing blank preamble lines.

### Phase 3: Remove Post-Diagnosis Agent GitHub Issue Reads

- Change: Update `implement.md` and `ui-verify.md` to read `CONTEXT_PATH` and
  local artifacts instead of running `gh issue view`.
- Compatibility: Review prompt already follows this model and should remain the
  reference pattern. Diagnosis may keep live issue/comment reads in V1.
- Acceptance criteria:
  - Tests assert implementation, review, UI verification, and repair prompts do
    not instruct agents to run `gh issue view`.
  - Tests assert prompts instruct agents not to run GitHub issue commands for
    contract discovery.
  - Existing phase completion promise behavior is unchanged.

### Phase 4: Allowed-Actions Consistency

- Change: Fix phase allowed actions so `ui-verify` is read-only and matches the
  UI verification prompt.
- Compatibility: The mechanical authority gate still blocks UI verification code
  edits.
- Acceptance criteria:
  - Tests assert `ui-verify` allowed actions contain no commit or fix language.
  - Tests assert `ui-verify` forbidden actions include code edits and commits.
  - Tests assert `ui-verify` references UI Integration Smoke selectors, not the
    full `WorkoutTrackerUITests` bundle.

### Phase 5: Focused Verification

- Change: Add narrow tests for the rendered prompt envelope and phase-boundary
  contracts.
- Compatibility: Avoid broad prompt snapshot tests and operator-doc churn.
- Acceptance criteria:
  - Ralph Python tests pass.
  - Tests cover the XML envelope shape and required `<forbidden_actions>`.
  - Tests cover the UI Integration Smoke boundary and the contract-discovery
    `gh issue view` removal.

## Deletion Criteria

- Any prompt instruction that tells a post-diagnosis phase agent to run
  `gh issue view` can be deleted once `issue-contract.md` and
  `issue-comments.md` carry equivalent captured context.
- Any compatibility language allowing live issue rereads during `implement-tdd`,
  `review`, or `ui-verify` can be deleted once prompt tests enforce the local
  context rule.
- Historical report/dashboard support is unaffected and has no deletion
  requirement in this spec.

## Acceptance Criteria

- [ ] Implementation, review, UI verification, and repair prompts no longer
      instruct agents to run `gh issue view <n> --comments`.
- [ ] Issue body, labels, comments, PRD directive, blockers, and UI-test edit
      authority are captured programmatically before agent phases.
- [ ] `issue-contract.md` clearly separates authority fields from context fields.
- [ ] Comments are rendered as context only, including comments labelled
      `Agent Brief`.
- [ ] Captured comments are available locally by path when needed.
- [ ] Phase prompt preambles use structured runtime, authority, action, reference,
      and completion sections.
- [ ] Every normal phase prompt is wrapped in the XML-style `<ralph_phase>`
      envelope.
- [ ] Every phase envelope includes explicit `<forbidden_actions>`.
- [ ] Context artifacts remain markdown while the prompt wrapper uses XML-style
      section tags.
- [ ] `ui-verify` allowed actions are read-only and do not mention commits or UI
      fixes.
- [ ] `ui-verify` points agents at UI Integration Smoke class-level selectors and
      does not ask them to run the full `WorkoutTrackerUITests` bundle.
- [ ] Focused prompt-rendering tests cover the XML wrapper, forbidden actions,
      UI Integration Smoke boundary, and no `gh issue view` contract-discovery
      instruction outside diagnosis.
- [ ] Existing PR-only publication, issue lifecycle labels, authority gates, and
      promise parsing behavior remain unchanged.

## Testing Strategy

Use Python unit tests for issue-context rendering, prompt envelope rendering, and
per-phase allowed/forbidden action lists. Keep prompt tests focused; do not add
broad prompt snapshot tests. The useful assertions are the contract points:
XML wrapper presence, required `<forbidden_actions>`, no full
`WorkoutTrackerUITests` bundle in `ui-verify`, no broad "do not run UI tests"
wording in `implement-tdd`, and no `gh issue view` contract-discovery
instruction outside diagnosis.

Existing loop, authority, review, repair, and publish tests should continue to
cover the state-machine behavior.

No live Ralph iteration is required to prove this spec. A live run would spend
agent time and mutate GitHub state; local prompt/context tests are the right
verification layer unless a later implementation changes GitHub API usage.

## Open Questions

- None.
