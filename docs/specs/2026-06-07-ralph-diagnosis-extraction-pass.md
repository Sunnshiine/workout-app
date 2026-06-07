# Ralph Diagnosis Extraction Pass Spec

## Goal

Make Ralph's bug-diagnosis handoff robust by **separating reasoning from
formatting**. Today the `diagnose` phase reasons about a bug *and* emits its
structured `<diagnosis-result>` artifact in one turn; a malformed artifact costs a
full re-run of the expensive reasoning. This spec splits diagnosis into two turns
— reason, then a dedicated **extraction turn** whose only job is to emit a
machine-parseable JSON artifact — so formatting noise can no longer corrupt the
handoff, and recovery from a bad artifact re-runs only the cheap extraction.

It also finishes the prompt slim begun in the predecessor spec by trimming the
residual runtime-fact restatement from `review.md`, with no behavior change.

This is a focused evolution of the diagnosis axis of
[the prompt-layer simplification](2026-06-06-ralph-prompt-layer-simplification.md),
not a re-do of it. Everything that spec shipped (cut `ui-verify`/`diagnose-format`,
bounded review loop, minimal `implement.md`, opt-in observations) stays as is.

## Background

Ralph is a Python PR orchestrator (see
[2026-06-05-ralph-python-pr-orchestrator.md](2026-06-05-ralph-python-pr-orchestrator.md))
that runs phase agents in an isolated worktree and owns gates, authority,
publishing, and lifecycle state. For `bug`-labelled issues it runs a `diagnose`
phase before implementation; the diagnosis must hand off `root_cause`, `fix_plan`,
`test_seam`, and a `Tests/UI/**` authority decision the host acts on.

The predecessor spec already replaced a free-text block with a *structured*
`<diagnosis-result>` artifact and replaced a dedicated `diagnose-format`
corrective phase with a single generic `diagnose` retry. That structured artifact
is, today, a **key:value text block emitted inline in the reasoning turn** and
parsed by `parse_diagnosis_authority` (`diagnosis.py:105`). The remaining weakness
is the entanglement: a `json`/format slip in a long reasoning response forces a
full re-diagnose (`loop.py:601-627`).

Relevant prior decisions and docs:

- [ADR-0009](../adr/0009-ralph-diagnosis-extraction-pass.md) — **the decision this
  spec implements.** Fresh-turn extraction (not session-resume, not inline JSON),
  chosen for engine-agnosticism and robustness.
- [ADR-0008](../adr/0008-ralph-stacked-blocked-by-chains.md) — stacked `Blocked by`
  chains. **Unchanged by this spec.**
- [2026-06-06-ralph-prompt-layer-simplification.md](2026-06-06-ralph-prompt-layer-simplification.md)
  — shipped the structured artifact, the bounded review loop, and the minimal
  `implement.md`. **This spec supersedes only its diagnosis approach** (single
  inline turn + one full re-diagnose retry).
- [2026-06-06-ralph-programmatic-issue-context-prompts.md](2026-06-06-ralph-programmatic-issue-context-prompts.md)
  — the controller-injected `phase-context.md` envelope this spec leans on as the
  single source of runtime facts.

The source material is an external deep-research review
(`~/Downloads/deep-research-report-2.md`) and a grilling session on 2026-06-07.
The review ranked typed diagnosis as its #1 change; grilling revised that — the
existing parser already classifies and retries, so the durable win is the
extraction *split*, not a schema for its own sake. The review's other headline
ideas (risk-based review, typed completion signal, hard-rules-via-hooks) were
verified against the code and **rejected** — see Scope/Out and Decisions.

## Decisions

- **Decision:** Diagnosis runs as two turns — a reasoning turn (`diagnose`) and a
  dedicated extraction turn (`diagnose-extract`) whose sole job is to emit the
  artifact.
  **Source:** [ADR-0009](../adr/0009-ralph-diagnosis-extraction-pass.md); grilling
  2026-06-07.
  **Consequence:** Formatting noise from reasoning can no longer corrupt the
  artifact. Each bug issue costs one extra short turn.

- **Decision:** The extraction turn is a **fresh `run_phase` call whose input is
  the prior turn's output**, not a resumed provider session.
  **Source:** ADR-0009. `CodexProviderSdkClient` tears its thread down per phase
  (`sdk_clients.py:54-57`) and `ClaudeProviderSdkClient` uses stateless `query()`
  with `max_turns=1` (`sdk_clients.py:88,94`); resuming would need engine-specific
  session machinery and break the `Engine.run_phase` seam.
  **Consequence:** Extraction runs identically under `codex` and `claude`; no SDK
  session plumbing is added. The diagnosis text is re-sent as extraction input.

- **Decision:** The artifact is a JSON object inside the `<diagnosis-result>` tag.
  **Source:** ADR-0009; grilling. The tag delimits the object even if the model
  adds stray prose; `json.loads` parses the inner content.
  **Consequence:** `parse_diagnosis_authority` parses JSON instead of key:value
  lines. Field names and classification are unchanged.

- **Decision:** On a malformed artifact, re-run **only the extraction turn**, up to
  2 retries (3 attempts total), then escalate to a blocked rescue PR.
  **Source:** Grilling 2026-06-07.
  **Consequence:** A formatting failure never re-runs the expensive reasoning. This
  replaces today's "re-diagnose once" path (`loop.py:601-627`).

- **Decision:** `diagnose.md` sheds the artifact-format block and both worked
  examples (they move to `diagnose-extract.md`) but **keeps "Must invoke the
  `diagnose` skill"** and all behavioral guidance.
  **Source:** Grilling 2026-06-07 (maintainer chose to keep the skill mandate).
  **Consequence:** The reasoning prompt shrinks; the curated diagnosis discipline
  is preserved as a hard instruction.

- **Decision:** `review.md` keeps every behavior — always-on, both reviewers,
  edit-in-place, single bounded rerun — and only sheds runtime-fact restatement
  the envelope already carries.
  **Source:** Grilling 2026-06-07.
  **Consequence:** Smaller prompt, identical behavior. Hard "do not" rules stay as
  prose (maintainer's call); they are not moved to hooks or host guards.

- **Decision (rejected):** Risk-based / conditional review. **Keep review
  always-on.**
  **Source:** Grilling 2026-06-07. A diff-risk classifier + thresholds + a label
  override is speculative configurability (YAGNI) at the current issue cadence; the
  cost it saves (a few reviewer subagent turns on trivial diffs) is not a measured
  pain.
  **Consequence:** No risk classifier is built. Out of scope.

- **Decision (rejected):** Typed `<result>` completion signal. **Keep promise
  lines.**
  **Source:** Grilling 2026-06-07. `parse_promise` (`engines.py:65`) already
  resolves a typed `PhaseStatus`, works on both engines, and the host re-runs gates
  regardless of any self-reported result. A typed payload would be churn the host
  ignores.
  **Consequence:** The completion mechanism is untouched. The diagnosis JSON is a
  *payload*, not a status signal.

- **Decision (rejected):** Hard-rules enforcement via hooks or a generalized
  host-side forbidden-path guard. **Hard rules stay as prompt prose.**
  **Source:** Grilling 2026-06-07. Claude Code / SDK hooks fire only for
  `--engine claude`, so they cannot be a guarantee while `codex` is a first-class
  engine; the maintainer chose prose over building an engine-agnostic host guard.
  **Consequence:** No hook and no new authority/guard module. Out of scope.

## Scope

### In

- Add a `diagnose-extract` phase: new prompt `ralph/prompts/diagnose-extract.md`,
  a `PHASE_DIAGNOSE_EXTRACT` constant, and its allowed/forbidden-action envelope
  entries.
- Change the `<diagnosis-result>` artifact from key:value text to a JSON object;
  update `parse_diagnosis_authority` to `json.loads` the tag's inner content while
  preserving classification.
- Rewire `_run_diagnosis` to the two-turn flow and the re-extract-only retry
  policy; remove the re-diagnose-on-malformed path.
- Slim `diagnose.md` (move the artifact block to the extraction prompt; keep the
  diagnose-skill mandate; strip envelope-redundant runtime facts).
- Slim `review.md` (remove residual runtime-fact restatement only).
- Update `ralph/README.md`'s diagnosis section (currently the inline key:value
  block and the "rerun the diagnose phase once" retry) to the two-turn extraction
  flow, and add the "extraction pass / extraction turn" vocabulary referenced by
  [ADR-0009](../adr/0009-ralph-diagnosis-extraction-pass.md).
- Update the Ralph Python tests that pin these surfaces.

### Out

- **Risk-based / conditional review** — rejected; review stays always-on.
- **Typed `<result>` completion signal** — rejected; promise lines stay.
- **Hooks / host-side forbidden-path enforcement** — rejected; hard rules stay as
  prompt prose.
- Everything the predecessor spec already shipped: `ui-verify` removal,
  `diagnose-format` removal, the bounded review loop, the minimal `implement.md`,
  opt-in observations.
- Issue selection, gate definitions/execution, PR-only publication, frozen
  `IssueContract` capture, simulator leasing, ADR-0008 stacked chains, the
  `AuthorityGate` mechanical check — all load-bearing, untouched.
- Engine adapters (`engines.py`, `sdk_clients.py`) beyond invoking the extraction
  turn through the existing `run_phase` path.
- The diagnosis field schema itself (`root_cause` / `fix_plan` / `test_seam` /
  `ui_integration_test_edits_required` / `scope` / `reason` / `blocked_reason`) —
  the fields are unchanged; only their serialization and the turn that emits them
  change.

## Current Architecture

Bug-diagnosis flow in `RalphLoop._run_diagnosis` (`loop.py:573-640`):

1. Run the `diagnose` phase (single turn). Its prompt (`diagnose.md`) instructs the
   agent to reason about the bug *and* end the response with one well-formed
   key:value `<diagnosis-result>` block (`diagnose.md:30-73`, both examples
   included).
2. Write the full response to `diagnosis.md`; call
   `parse_diagnosis_authority(result.final_response)` (`diagnosis.py:105`), which
   regex-locates the tag and reads it line-by-line (`_parse_fields`,
   `diagnosis.py:234`).
3. On `needs_corrective_pass` (malformed): **re-run the entire `diagnose` turn
   once** with the parser error appended (`loop.py:601-616`); re-parse; a second
   failure → blocked rescue PR (`loop.py:617-627`).
4. On `needs_human_escalation` (`OUT_OF_SCOPE`): blocked rescue PR
   (`loop.py:629-637`).
5. Otherwise grant `Tests/UI/**` authority if requested (`_grant_ui_authority`,
   `loop.py:642`) and recapture the contract.

Downstream `implement` → `review` and the gate/authority/repair/publish stack are
unchanged by this spec. Each phase prompt is wrapped by the controller-injected
`phase-context.md` envelope carrying runtime facts, allowed/forbidden actions, and
the promise-line completion contract (`prompt_context.render_phase_context`).

## Target Architecture

Bug-diagnosis flow becomes:

1. Run the `diagnose` phase (reasoning only). `diagnose.md` no longer describes the
   artifact format; it produces the handoff narrative (repro, cause, fix plan,
   regression seam) and still invokes the `diagnose` skill.
2. Write the diagnose output to `diagnosis.md` (the implementation handoff, as
   today).
3. Run the new `diagnose-extract` phase. Its input is the diagnose turn's output;
   its sole job is to emit one `<diagnosis-result>` tag containing a JSON object.
4. Parse the **extraction turn's** output with `parse_diagnosis_authority`
   (`json.loads` the tag inner). Classification is unchanged.
5. On a malformed artifact, re-run **only** `diagnose-extract`, up to 2 retries,
   then a blocked rescue PR. The diagnose reasoning is never re-run for a
   formatting failure.
6. `OUT_OF_SCOPE` escalation, `Tests/UI/**` authority grant, audit comment, and
   contract recapture are all unchanged.

`review.md` is trimmed of runtime-fact restatement; its behavior (both reviewers,
single bounded rerun, edit-in-place) is unchanged. Promise-line completion is
unchanged for every phase.

## Contracts

### Diagnosis artifact [CHANGED]

The tag wrapper is kept; its contents change from key:value text to a JSON object.
Field names, requiredness, and `Tests/UI/**`-only scope are **unchanged** from
today's contract.

Before (`diagnose.md`, inline in the reasoning turn):

```text
<diagnosis-result>
root_cause: The tap handler never reaches the visible writable row.
fix_plan: Route the gesture through the real control instead of the overlay.
test_seam: Tests/UI integration — the visible state only renders in the UI.
ui_integration_test_edits_required: true
scope: Tests/UI/WorkoutTrackerUITests.swift
reason: Lower-level coverage cannot prove the route, per docs/TESTING.md.
</diagnosis-result>
```

After (`diagnose-extract.md`, emitted by the extraction turn):

```text
<diagnosis-result>
{
  "root_cause": "The tap handler never reaches the visible writable row.",
  "fix_plan": "Route the gesture through the real control instead of the overlay.",
  "test_seam": "Tests/UI integration — the visible state only renders in the UI.",
  "ui_integration_test_edits_required": true,
  "scope": ["Tests/UI/WorkoutTrackerUITests.swift"],
  "reason": "Lower-level coverage cannot prove the route, per docs/TESTING.md."
}
</diagnosis-result>
```

Field contract (unchanged semantics):

- `root_cause`, `fix_plan`, `test_seam` — strings, required and non-empty.
- `ui_integration_test_edits_required` — boolean, required.
- `scope` — array of strings, required **iff** required is `true`; every path must
  be under `Tests/UI/**` (any other path → `OUT_OF_SCOPE`, escalate to human).
- `reason` — string, required **iff** required is `true`.
- `blocked_reason` — string, optional; set only when diagnosis itself is blocked.

Parse classification preserved from `DiagnosisAuthorityStatus`
(`diagnosis.py:48-65`): `NOT_REQUIRED`, `GRANT_UI_TESTS`, `OUT_OF_SCOPE`,
`MALFORMED`.

### `parse_diagnosis_authority` [CHANGED]

- Locates the first `<diagnosis-result>` tag (unchanged), then `json.loads` the
  inner object instead of reading key:value lines. Non-JSON or schema-invalid
  content → `MALFORMED` with the `json`/validation error as `error`.
- `DiagnosisAuthority`, `DiagnosisAuthorityParse`, the status enum,
  `apply_ui_test_authority`, and `render_authority_comment` are unchanged.
- The key:value helpers `_parse_fields` / `_parse_bool` / `_parse_scope`
  (`diagnosis.py:234-257`) are removed.

### Phase set [CHANGED]

```text
[KEPT]   PHASE_DIAGNOSE         ("diagnose",         diagnose.md)          # bug-only, reason
[ADDED]  PHASE_DIAGNOSE_EXTRACT ("diagnose-extract", diagnose-extract.md)  # bug-only, extract
[KEPT]   PHASE_IMPLEMENT        ("implement-tdd",    implement.md)
[KEPT]   PHASE_REVIEW           ("review",           review.md)
```

`diagnose-extract` is invoked only inside `_run_diagnosis`, never added to the
`implement` → `review` iteration tuple (`loop.py:365-367`).

### Extraction turn input/output [ADDED]

- **Input:** the diagnose turn's `final_response` (the same text written to
  `diagnosis.md`). Whether it is injected inline into the extraction prompt or
  referenced via the `diagnosis.md` artifact path is an implementation choice;
  inline injection is preferred for robustness (a file read can fail). The
  extraction turn does not re-diagnose, edit code, or commit.
- **Output:** exactly one `<diagnosis-result>` tag containing the JSON object
  above, and nothing else of significance. Phase completion still uses the
  promise-line contract from the envelope.

### Retry policy [CHANGED]

```text
diagnose (reason)  →  diagnose-extract (attempt 1)
                          └─ malformed → diagnose-extract (retry 1)
                                            └─ malformed → diagnose-extract (retry 2)
                                                              └─ malformed → BLOCKED rescue PR
```

Replaces the current "re-run `diagnose` once on malformed, then block"
(`loop.py:601-627`). Reasoning is never re-run for a formatting failure.

## Migration Plan

Harness Python plus prompt text — not a data migration. Phases are ordered so the
`ralph/tests` suite stays green at each step.

### Phase 1: Add the `diagnose-extract` phase (inert)

- **Change:** Add `ralph/prompts/diagnose-extract.md` carrying the JSON schema and
  both worked examples; add `PHASE_DIAGNOSE_EXTRACT` and its
  `_allowed_actions_for_phase` / `_forbidden_actions_for_phase` entries (read +
  emit artifact; no edit/commit/diagnose). Do not wire it into `_run_diagnosis`
  yet.
- **Compatibility:** Nothing invokes the phase; live behavior unchanged.
- **Acceptance criteria:** A prompt-contract test for `diagnose-extract.md` exists
  (forbids edit/commit, requires the JSON artifact); suite green.

### Phase 2: JSON artifact + two-turn rewire (atomic)

- **Change:** Switch `parse_diagnosis_authority` to `json.loads` the tag inner;
  rewire `_run_diagnosis` to run `diagnose` then `diagnose-extract`, parse the
  extraction output, and re-run only `diagnose-extract` up to 2 retries before a
  blocked rescue PR. Remove the re-diagnose-on-malformed branch and the key:value
  helpers.
- **Compatibility:** `OUT_OF_SCOPE` / `GRANT_UI_TESTS` classification, the
  issue-body grant, the audit comment, and contract recapture are preserved. This
  step lands the parser and loop change together because they are inseparable.
- **Acceptance criteria:** `test_diagnosis.py` uses JSON fixtures across all four
  classifications; `test_diagnosis_loop.py` asserts diagnose runs once, a malformed
  artifact triggers ≤2 extraction re-runs then escalates, and the reasoning turn is
  never re-run on a formatting failure; suite green.
- **Docs:** `ralph/README.md`'s diagnosis section is updated to the two-turn flow,
  the JSON artifact example, and the re-extract retry, with the extraction-pass
  vocabulary added. The README tracks shipped behavior, so it changes here, not in
  Phase 1.

### Phase 3: Slim `diagnose.md`

- **Change:** Remove the `<diagnosis_artifact_instructions>` block and both
  examples (now in `diagnose-extract.md`); adjust `<completion_gate>` to drop the
  artifact requirement; strip envelope-redundant runtime facts. **Keep "Must
  invoke the `diagnose` skill"** and the behavioral guidance.
- **Compatibility:** The extraction turn owns the artifact; the reasoning turn only
  needs to produce an actionable handoff.
- **Acceptance criteria:** `test_diagnose_prompt.py` asserts no artifact-format
  text remains and the diagnose-skill mandate is retained; suite green.

### Phase 4: Slim `review.md`

- **Change:** Remove the residual runtime-fact restatement (the `<role>`
  preamble-fact recap and the `<contract>` references to `ISSUE_BASE_REF`,
  contract-path-as-authority, and Branch Directive that the envelope already
  carries). Keep both-reviewer spawning, edit-in-place, the single bounded rerun,
  the behavioral "do not" rules, and the completion gate.
- **Compatibility:** Behavior identical; only prose the envelope duplicates is
  removed.
- **Acceptance criteria:** `test_review_prompt.py` still asserts both reviewers and
  the single-rerun bound; new assertions confirm the removed runtime-fact prose is
  gone; suite green.

## Deletion Criteria

- `_parse_fields` / `_parse_bool` / `_parse_scope` (`diagnosis.py:234-257`) —
  delete in Phase 2 when JSON parsing lands.
- The re-diagnose-on-malformed branch (`loop.py:601-627`) — delete in Phase 2 when
  the re-extract retry replaces it.
- The `<diagnosis_artifact_instructions>` block and examples in `diagnose.md`
  (`diagnose.md:30-73`) — delete in Phase 3 once `diagnose-extract.md` owns the
  format.

## Acceptance Criteria

- [ ] A bug issue runs `diagnose` (reasoning) followed by a separate
      `diagnose-extract` turn; the artifact comes from the extraction turn, not the
      reasoning turn.
- [ ] The `<diagnosis-result>` artifact is a JSON object parsed by `json.loads`;
      all four classifications (`NOT_REQUIRED`, `GRANT_UI_TESTS`, `OUT_OF_SCOPE`,
      `MALFORMED`) are produced from JSON input.
- [ ] A malformed artifact re-runs **only** `diagnose-extract`, at most twice, then
      escalates to a blocked rescue PR; the `diagnose` reasoning turn is never
      re-run for a formatting failure.
- [ ] `Tests/UI/**` authority grant, the audit comment, `OUT_OF_SCOPE` escalation,
      and contract recapture behave exactly as before.
- [ ] `diagnose.md` retains "Must invoke the `diagnose` skill" and no longer
      contains any `<diagnosis-result>` format instructions or examples.
- [ ] `diagnose-extract.md` forbids editing/committing/diagnosing and requires the
      single JSON artifact.
- [ ] `review.md` still spawns both `swift-reviewer` and
      `spec-conformance-reviewer` with the single bounded rerun; only runtime-fact
      restatement is removed.
- [ ] Promise-line completion is unchanged for all phases.
- [ ] `ralph/README.md`'s diagnosis section reflects the two-turn extraction flow,
      the JSON artifact, and the re-extract retry; no stale key:value example or
      "rerun the diagnose phase once" text remains.
- [ ] The full Ralph Python suite (`python -m pytest ralph/tests`) is green.

## Testing Strategy

Verification is the existing `ralph/tests/` suite; each phase updates the tests
pinning its surface and keeps the suite green before the next.

- Diagnosis core (`test_diagnosis.py`): JSON parsing across all four
  classifications, including `OUT_OF_SCOPE` for non-`Tests/UI/**` scope and
  `MALFORMED` for non-JSON / schema-invalid input.
- Diagnosis loop (`test_diagnosis_loop.py`): two-turn ordering, ≤2 extraction
  re-runs then escalation, no reasoning re-run on a formatting failure, preserved
  authority-grant/recapture behavior.
- Prompt contracts (`test_diagnose_prompt.py`, a new `diagnose-extract` prompt
  test, `test_review_prompt.py`, `test_ralph_prompt_contracts.py`,
  `test_phase_envelope.py`): the slimmed `diagnose.md`, the extraction prompt's
  forbidden actions + required JSON artifact, the retained review behavior, and the
  new phase's envelope wiring.

No Swift or simulator change is in scope; the Xcode gate stack is unaffected.

## Open Questions

- None blocking. Inline injection vs `diagnosis.md`-path reference for the
  extraction turn's input is an implementation choice (inline preferred for
  robustness), deferred to `to-issues`/implementation. The JSON serialization and
  the field schema are fixed above.
