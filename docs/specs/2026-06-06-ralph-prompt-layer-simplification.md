# Ralph Prompt-Layer Simplification Spec

## Goal

Make the Ralph harness **controller-thick, prompt-thin**. The control layer
(`ralph/orchestrator/`) already owns issue selection and gate execution
deterministically; the remaining bloat lives in the phase prompts under
`ralph/prompts/` — duplicated policy, redundant phases, and always-on
boilerplate. This spec removes a redundant phase, bounds an unbounded loop,
replaces a free-text handoff with a structured artifact, makes telemetry
opt-in, and shrinks the prompts so each retained sentence is load-bearing.

The driving observation: the loop already enforces selection
(`IssueSelector.select_next`, `loop.py:121-158`) and gates (`_gate_specs`,
`loop.py:898-968`) in pure Python. Several prompts still narrate that policy or
duplicate the controller-injected prompt envelope. We cut the duplication, not
the controls.

## Background

Ralph is a Python PR orchestrator (see
[docs/specs/2026-06-05-ralph-python-pr-orchestrator.md](2026-06-05-ralph-python-pr-orchestrator.md))
that polls `ready-for-agent` issues, claims one, runs phase agents in an
isolated worktree, runs deterministic gates, and publishes only via pull
requests. Phase prompts live in `ralph/prompts/`; the controller wraps each one
in a generated XML envelope
(`RalphLoop._phase_prompt`, `loop.py:501-572`) carrying runtime facts,
`<allowed_actions>`, `<forbidden_actions>`, and the `<completion_contract>`.

Relevant prior decisions and specs:
- [ADR-0008](../adr/0008-ralph-stacked-blocked-by-chains.md) — stacked
  `Blocked by` chains accrete onto a root PR. **Unchanged by this spec.**
- [docs/specs/2026-06-05-ralph-review-phase-spec-conformance.md](2026-06-05-ralph-review-phase-spec-conformance.md)
  — the two-reviewer review phase. **Amended here** (loop bound, not removed).
- [docs/specs/2026-06-06-ralph-programmatic-issue-context-prompts.md](2026-06-06-ralph-programmatic-issue-context-prompts.md)
  and [docs/specs/2026-06-06-ralph-prompt-body-xml-tagging.md](2026-06-06-ralph-prompt-body-xml-tagging.md)
  — the controller-injected prompt envelope this spec leans on as the single
  source for allowed/forbidden actions.
- [docs/specs/2026-06-06-ui-integration-smoke-ralph-gate.md](2026-06-06-ui-integration-smoke-ralph-gate.md)
  — the controller-owned UI Integration Smoke gate that makes the `ui-verify`
  phase redundant.

The source material for this simplification is an external deep-research review
of the harness (`~/Downloads/deep-research-report.md`). Two of its headline
recommendations (move selection to Python; move gates to Python) were verified
as **already implemented**, so they are out of scope. One recommendation (cut
AGENTS.md's Swift conventions) was **rejected** after verifying Ralph runs the
Codex engine — see Decisions.

## Decisions

- **Decision:** Cut the `ui-verify` phase entirely.
  **Source:** Grilling session 2026-06-06; the phase reruns the same UI smoke
  selectors the controller already runs as `GATE_UI_INTEGRATION`
  (`ui-verify.md:48-57` vs `loop.py:943-968`), and a smoke failure inside the
  phase blocks the issue immediately (`loop.py:388-397`) where the identical
  failure as a gate gets a UI-owned repair attempt (`loop.py:420-439`).
  **Consequence:** UI smoke runs once (as the gate); UI-smoke failures now flow
  into the existing repair loop instead of an instant block; one model turn and
  one slow simulator run removed per issue.

- **Decision:** Keep both reviewers (`swift-reviewer` +
  `spec-conformance-reviewer`) but bound the re-review loop to a single
  repair+rerun, then BLOCK.
  **Source:** Grilling session; the lenses are distinct (technical idiom vs
  frozen-contract conformance — the latter is the most likely drift in
  unattended work), but `review.md:43` loops unbounded.
  **Consequence:** Contract-conformance coverage retained; worst-case review
  cost is bounded.

- **Decision:** Diagnosis emits a structured, parseable artifact; on parse
  failure run one generic retry of the `diagnose` prompt; delete the dedicated
  `diagnose-format` corrective phase.
  **Source:** Grilling session; `diagnose-format.md` is a whole extra model turn
  whose only job is re-emitting a malformed free-text `<diagnosis-authority>`
  block (`loop.py:601-627`).
  **Consequence:** Malformed authority no longer needs a bespoke prompt; one
  generic retry path replaces a specialized phase.

- **Decision:** Observations are opt-in (block/retry/reusable-friction only);
  the controller writes routine success metadata.
  **Source:** Grilling session; `implement.md:60-66`, `review.md:47-52` require
  an `<observations>NONE</observations>` block on every successful run.
  **Consequence:** Less prompt/response boilerplate on every clean issue; the
  failure-note path is unchanged.

- **Decision:** The controller-injected envelope (`<allowed_actions>` /
  `<forbidden_actions>`) is the single source of truth for what a phase may do;
  prose restatements are stripped from prompt bodies.
  **Source:** Grilling session; `loop.py:1089-1153` injects the rules and
  `implement.md:50-53` (and peers) restate them in prose — two sources for one
  rule.
  **Consequence:** No drift risk when one copy is edited; bodies keep "how/why",
  not the "what's allowed" list.

- **Decision:** Doc reads in prompt bodies become conditional; only "the frozen
  contract is authority" stays mandatory.
  **Source:** Grilling session; `implement.md:33-39` unconditionally reads
  CONTEXT.md, ADRs, AGENTS.md/CLAUDE.md, and PRD on every issue.
  **Consequence:** Lower always-on context load; domain/ADR reads happen only
  for the area touched.

- **Decision:** Rewrite `implement.md` to the minimal template **plus one
  conditional domain line**.
  **Source:** Grilling session reconciling "full minimal rewrite" with "keep a
  conditional CONTEXT.md read" — the powerlifting glossary in `CONTEXT.md`
  (e.g. *Move On* ≠ Finish, *Visible Writable Row*, Superset dissolution) is
  non-obvious domain language an agent cannot infer.
  **Consequence:** `implement.md` shrinks from 84 lines to ~8; domain grounding
  preserved by a single conditional line.

- **Decision:** Delete the dead `select.md` template.
  **Source:** Selection is pure Python (`IssueSelector.select_next`); nothing in
  `ralph/orchestrator/` reads `select.md`.
  **Consequence:** Removes a misleading file implying an LLM selection turn that
  does not exist.

- **Decision (rejected cut):** **Keep** AGENTS.md's generic Swift sections
  (`AGENTS.md:108-298`).
  **Source:** Ralph supports the Codex engine (`engines.py:37-40`,
  `sdk_clients.py:37-64`). Codex auto-loads `AGENTS.md`, not the user's
  `~/.claude/rules/swift/`; nothing in `ralph/orchestrator/` injects those
  global rules. For Codex runs, AGENTS.md is the **sole** source of those
  conventions.
  **Consequence:** AGENTS.md Swift content is out of scope for cutting. It is
  deliberate, load-bearing duplication for the Codex transport — do not "clean
  it up".

## Scope

### In

- Cutting the `ui-verify` phase and `ui-verify.md`.
- Bounding the review re-review loop and trimming `review.md`.
- Replacing the diagnosis free-text authority block with a structured artifact;
  deleting `diagnose-format.md` and its corrective branch in `loop.py`.
- Making the observations block opt-in across remaining prompts.
- Stripping allowed/forbidden prose duplication from prompt bodies.
- Making doc reads conditional in remaining prompts.
- Minimal rewrite of `implement.md`.
- Deleting `select.md`.
- Updating the Ralph Python tests that assert on the above surfaces.

### Out

- Issue selection logic (already pure Python).
- Gate definitions and execution (already controller-owned).
- PR-only publication, frozen `IssueContract` capture, simulator leasing,
  bug-only diagnosis routing — all load-bearing, untouched.
- ADR-0008 stacked-chain behavior.
- AGENTS.md Swift conventions (kept for Codex; see Decisions).
- Any change to the engine adapters (`engines.py`, `sdk_clients.py`) beyond what
  the diagnosis-artifact parse requires.
- No new ADR is created for this work (per maintainer's call).

## Current Architecture

Per-issue flow in `RalphLoop._run_issue` (`loop.py:342-443`):

1. Create worktree from the ADR-0008 target base ref.
2. If `bug`-labelled: run `diagnose` → write `diagnosis.md` → parse free-text
   `<diagnosis-authority>` block → on malformed block run the `diagnose-format`
   corrective phase once (`loop.py:592-627`) → grant `Tests/UI/**` authority if
   requested → recapture contract.
3. Run phases in sequence: `implement` → `review` → `ui-verify`
   (`loop.py:369-392`). `ui-verify` recomputes a `ui_phase_base`/`ui_phase_tip`
   window used by the authority check.
4. `AuthorityGate` mechanically enforces `Tests/UI/**` edit authorization over
   committed diffs (`loop.py:673-703`).
5. `_run_gates` runs `swift test`, `xcodegen`, unit/component, visual
   regression, **UI integration smoke**, swiftlint (`loop.py:705-715`,
   `898-968`).
6. On a UI-owned gate failure, one-shot repair runs (`loop.py:717-754`).
7. Publish success PR, or a blocked rescue PR.

Each phase prompt body (`ralph/prompts/*.md`) is wrapped by
`_phase_prompt` (`loop.py:501-572`) in an envelope that already carries
`<allowed_actions>`, `<forbidden_actions>`, and the `<completion_contract>` —
yet several bodies restate those same constraints in prose.

## Target Architecture

Per-issue flow becomes:

1. Create worktree (unchanged).
2. If `bug`-labelled: run `diagnose` → diagnosis emits a **structured authority
   artifact** → parse it → on parse failure run **one generic `diagnose`
   retry** (same prompt, parser-error appended) → grant `Tests/UI/**` authority
   if requested → recapture contract. **No `diagnose-format` phase.**
3. Run phases in sequence: `implement` → `review`. **No `ui-verify` phase.**
4. `AuthorityGate` enforces `Tests/UI/**` authorization over the full issue diff
   (`issue_base..issue_tip`). The separate `ui_phase_base`/`ui_phase_tip` window
   is removed; UI-test authorization is now evaluated over the whole issue diff,
   which is strictly simpler and equally safe (the gate already reads committed
   diffs, never prompt compliance).
5. `_run_gates` runs the same gate stack, including UI integration smoke — now
   the **single** place UI smoke executes.
6. Repair on UI-owned gate failure (unchanged) — and now this is the path a
   UI-smoke failure reaches, instead of an instant phase block.
7. Publish (unchanged).

Review keeps both reviewers but the in-prompt remediation loop is bounded: at
most one repair+rerun cycle, then COMPLETE (clean) or BLOCKED.

Prompt bodies describe **the work**, not the operating system. Allowed/forbidden
actions, runtime facts, and completion contract come only from the
controller-injected envelope.

## Contracts

### Diagnosis authority artifact [CHANGED]

The `diagnose` phase currently emits a free-text block parsed by
`parse_diagnosis_authority` (`diagnosis.py:99-156`):

```text
<diagnosis-authority>
ui_integration_test_edits_required: true
scope: Tests/UI/WorkoutTrackerUITests.swift
reason: Why lower-level coverage cannot prove the fix.
</diagnosis-authority>
```

Target: the `diagnose` phase emits a single parseable object carrying the full
handoff plus the authority decision. Field names below are the contract; the
serialization (fenced `json` or `yaml`) is an implementation choice for
`to-issues`/implementation, but it MUST be machine-parseable in one pass.

```yaml
root_cause: <concise statement of the diagnosed cause>
fix_plan: <the intended fix approach>
test_seam: <where the regression test attaches>
ui_integration_test_edits_required: true | false
scope: [Tests/UI/...]          # required iff required==true; paths only under Tests/UI/**
reason: <required iff required==true; why lower-level coverage can't prove the fix>
blocked_reason: <optional; set only when diagnosis itself is blocked>
```

Parse classification is preserved from the current
`DiagnosisAuthorityStatus` enum (`diagnosis.py:46-62`): `NOT_REQUIRED`,
`GRANT_UI_TESTS`, `OUT_OF_SCOPE` (escalate to human), and a parse failure.

- **Parse failure handling [CHANGED]:** instead of routing to a `diagnose-format`
  phase, the loop reruns the **`diagnose`** prompt **once**, appending the parser
  error as context. A second parse failure → blocked rescue PR (same escalation
  shape as today's "still invalid after corrective pass", `loop.py:617-624`).
- **`OUT_OF_SCOPE` and `GRANT_UI_TESTS` semantics are unchanged.** Authority is
  still limited to `Tests/UI/**`; the issue-body grant
  (`apply_ui_test_authority`) and audit comment (`render_authority_comment`) are
  unchanged.

### Prompt envelope as single authority [CHANGED]

`<allowed_actions>` / `<forbidden_actions>` injected by `_phase_prompt`
(`loop.py:501-572`, populated from `_allowed_actions_for_phase` /
`_forbidden_actions_for_phase`, `loop.py:1089-1153`) remain the authority. Prompt
bodies MUST NOT restate them. The `ui-verify` entries in those two functions are
**[REMOVED]**; the `diagnose-format` entries are **[REMOVED]**.

### Phase set [CHANGED]

```text
[REMOVED]  PHASE_UI_VERIFY      ("ui-verify",        ui-verify.md)
[REMOVED]  PHASE_DIAGNOSE_FORMAT("diagnose-format",  diagnose-format.md)
[KEPT]     PHASE_DIAGNOSE       ("diagnose",         diagnose.md)        # bug-only
[KEPT]     PHASE_IMPLEMENT      ("implement-tdd",    implement.md)
[KEPT]     PHASE_REVIEW         ("review",           review.md)          # bounded loop
```

The phase iteration tuple in `_run_issue` (`loop.py:369-373`) drops the
`ui-verify` entry. The UI-phase base/tip tracking (`loop.py:366-392`,
`399-417`) is removed; `_check_authority` is called with the single
`issue_base..issue_tip` range.

### Observations [CHANGED]

Removed from the mandatory completion gate of every prompt. An observations
block is emitted by an agent **only** on a block, a retry, or concrete reusable
friction. Routine success metadata is written by the controller. The
`observations.md` log path plumbing (`loop.py:525`, `558`) stays for the
opt-in case.

## Migration Plan

Not a data migration; these are independently shippable harness changes. Order
minimizes coupling. Each phase keeps the Ralph Python test suite green.

### Phase 1: Delete dead `select.md`

- **Change:** Remove `ralph/prompts/select.md`. Remove/adjust any test that
  asserts its existence or content.
- **Compatibility:** None needed — file is unread by the loop.
- **Acceptance criteria:** `select.md` gone; `grep -rn "select.md" ralph/`
  returns nothing in source; suite green.

### Phase 2: Strip envelope duplication + conditional reads from prompt bodies

- **Change:** Remove prose restatements of allowed/forbidden actions and the
  unconditional doc-read checklist from `implement.md`, `review.md`,
  `diagnose.md`. Make domain/ADR reads conditional.
- **Compatibility:** Envelope already injects the authoritative action lists; no
  behavior change for the agent's permissions.
- **Acceptance criteria:** Prompt-contract tests
  (`test_ralph_prompt_contracts.py`, `test_phase_envelope.py`,
  `test_implement_prompt.py`, `test_review_prompt.py`,
  `test_diagnose_prompt.py`) updated and green; no body restates an envelope
  action list.

### Phase 3: Observations opt-in

- **Change:** Remove the mandatory observations block from prompt completion
  gates; controller writes routine success metadata.
- **Compatibility:** Failure/retry observation path unchanged.
- **Acceptance criteria:** A successful phase produces no `NONE` observations
  block; failure paths still capture notes; relevant tests updated and green.

### Phase 4: Bound the review loop

- **Change:** `review.md` keeps both reviewers but caps remediation at one
  repair+rerun, then COMPLETE (clean) or BLOCKED. Update completion-gate wording.
- **Compatibility:** Both reviewer lenses retained; only the loop bound changes.
- **Acceptance criteria:** `test_review_prompt.py` asserts the single-rerun
  bound; suite green.

### Phase 5: Cut `ui-verify`

- **Change:** Remove `PHASE_UI_VERIFY` from the phase tuple, delete
  `ui-verify.md`, remove `ui-verify` entries from
  `_allowed_actions_for_phase`/`_forbidden_actions_for_phase`, and remove the
  `ui_phase_base`/`ui_phase_tip` tracking; call `_check_authority` over
  `issue_base..issue_tip`.
- **Compatibility:** UI smoke still runs as `GATE_UI_INTEGRATION`; UI-smoke
  failures now reach the repair path. `AuthorityGate` still blocks unauthorized
  `Tests/UI/**` edits over the full issue diff.
- **Acceptance criteria:** `test_ui_verify_prompt.py` removed;
  `test_authority.py`, `test_loop.py`, `test_ui_smoke_policy.py`,
  `test_repair.py` updated to the single-window authority + repair-on-UI-smoke
  behavior; suite green.

### Phase 6: Structured diagnosis artifact + delete `diagnose-format`

- **Change:** Update `diagnose.md` to emit the structured artifact; update
  `diagnosis.py`/`loop.py` to parse it and, on parse failure, rerun `diagnose`
  once with the parser error appended; delete `diagnose-format.md`,
  `PHASE_DIAGNOSE_FORMAT`, and the corrective branch (`loop.py:601-627`).
- **Compatibility:** `OUT_OF_SCOPE`/`GRANT_UI_TESTS` classifications and the
  issue-body grant/audit-comment behavior are preserved.
- **Acceptance criteria:** `test_diagnose_format_prompt.py` removed;
  `test_diagnosis.py`, `test_diagnosis_loop.py`, `test_diagnose_prompt.py`
  updated; a malformed artifact triggers exactly one `diagnose` retry then
  escalates; suite green.

## Deletion Criteria

- `ralph/prompts/select.md` — delete in Phase 1 (already dead).
- `ralph/prompts/ui-verify.md`, `PHASE_UI_VERIFY`, its action-list entries, and
  the `ui_phase_base/tip` tracking — delete once UI smoke is confirmed to run
  solely as the gate and `AuthorityGate` covers the full issue diff (Phase 5).
- `ralph/prompts/diagnose-format.md`, `PHASE_DIAGNOSE_FORMAT`, and the
  corrective branch — delete once the structured artifact + single `diagnose`
  retry replaces the corrective pass (Phase 6).
- Mandatory observations wording — delete from each prompt's completion gate in
  Phase 3.

## Acceptance Criteria

- [ ] UI Integration Smoke executes exactly once per issue (as the gate), and a
      smoke failure reaches the existing UI-owned repair path rather than an
      instant phase block.
- [ ] The active phase set is `diagnose` (bug-only) → `implement` → `review`;
      `ui-verify` and `diagnose-format` no longer exist as phases or prompt
      files.
- [ ] `AuthorityGate` still blocks an unauthorized `Tests/UI/**` edit, evaluated
      over the full `issue_base..issue_tip` diff.
- [ ] The `review` phase still invokes both `swift-reviewer` and
      `spec-conformance-reviewer`, and its remediation loop is bounded to one
      repair+rerun before COMPLETE/BLOCKED.
- [ ] `diagnose` emits a single machine-parseable artifact; a malformed artifact
      triggers exactly one `diagnose` retry, then escalates to a blocked rescue
      PR.
- [ ] A successful phase emits no observations block; block/retry/friction paths
      still capture notes.
- [ ] No prompt body restates the envelope's allowed/forbidden action lists; doc
      reads other than the frozen contract are conditional.
- [ ] `implement.md` is the minimal template plus one conditional CONTEXT.md/ADR
      line.
- [ ] `select.md` is deleted.
- [ ] AGENTS.md Swift sections are unchanged.
- [ ] The full Ralph Python suite (`python -m pytest ralph/tests`) is green.

## Testing Strategy

This is harness Python plus prompt text; verification is the existing
`ralph/tests/` suite. Each migration phase updates the tests that pin the
changed surface and keeps the suite green before the next phase:

- Prompt-contract tests (`test_ralph_prompt_contracts.py`,
  `test_phase_envelope.py`, `test_implement_prompt.py`, `test_review_prompt.py`,
  `test_diagnose_prompt.py`) pin envelope-as-authority, conditional reads,
  opt-in observations, and the minimal `implement.md`.
- Loop/authority/repair tests (`test_loop.py`, `test_authority.py`,
  `test_repair.py`, `test_ui_smoke_policy.py`) pin the `ui-verify` removal, the
  single-window authority check, and repair-on-UI-smoke routing.
- Diagnosis tests (`test_diagnosis.py`, `test_diagnosis_loop.py`) pin the
  structured artifact, single-retry-on-malformed, and preserved
  `OUT_OF_SCOPE`/`GRANT_UI_TESTS` behavior.
- Removed tests: `test_ui_verify_prompt.py`, `test_diagnose_format_prompt.py`.

No Swift/simulator change is in scope, so the Xcode gate stack is unaffected
beyond running once instead of twice.

## Open Questions

- None blocking. Serialization format for the diagnosis artifact (fenced `json`
  vs `yaml`) is an implementation choice deferred to `to-issues`/implementation;
  the field contract is fixed above.
