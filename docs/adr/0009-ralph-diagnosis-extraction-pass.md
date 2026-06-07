# ADR 0009: Ralph Diagnosis Uses a Fresh-Turn Extraction Pass for the Typed Artifact

**Status:** Accepted
**Date:** 2026-06-07

## Context

A `bug`-labelled issue runs a `diagnose` phase before implementation. That phase
must hand off a structured result — `root_cause`, `fix_plan`, `test_seam`, and a
`ui_integration_test_edits_required` authority decision (with `scope`/`reason`
when true) — which the host uses to grant `Tests/UI/**` authority, write the
implementation handoff, and feed review.

Today that result is a free-text key:value `<diagnosis-result>` block emitted at
the end of the reasoning response and parsed by `diagnosis.py`
(`parse_diagnosis_authority`). The parser is already more robust than the
deep-research report assumed: it classifies the artifact (`not-required` /
`grant-ui-tests` / `malformed` / `out-of-scope`) and `loop.py` already re-runs the
diagnose phase **once** on a malformed artifact before escalating. The remaining
weakness is that formatting and reasoning are entangled in one turn, and a
formatting failure pays for a full re-run of the expensive reasoning.

The engine abstraction is deliberately narrow: `Engine.run_phase` runs **one**
prompt in **one** worktree and returns **one** `PhaseResult`. The two real
engines reflect this — `CodexProviderSdkClient` opens a thread, runs it, and tears
it down inside a single `with Codex()` block (`sdk_clients.py`), and
`ClaudeProviderSdkClient` uses the stateless `query()` with `max_turns=1`.

Alternatives considered:

- **Session-resume extraction** (Sandcastle's literal `runWithExtraction`, which
  resumes the same conversation and asks it to reformat). Rejected: resuming would
  require engine-specific session machinery — keeping the Codex thread alive across
  calls and switching Claude to its stateful client API — which breaks the
  engine-agnostic seam that is the whole point of `Engine.run_phase`.
- **Inline JSON in the single diagnose turn.** Rejected: a reasoning-heavy
  response that ends in JSON routinely picks up markdown fences or trailing commas,
  and `json.loads` is stricter than today's lenient line parser — so this is churn
  that can *regress* robustness rather than improve it.
- **Keep the current key:value block.** Rejected as the chosen direction (it is
  the YAGNI baseline) because it leaves formatting entangled with reasoning and
  keeps the expensive re-diagnose-on-malformed recovery.

## Decision

Diagnosis becomes two turns: **reason, then extract.**

- **Reason.** The `diagnose` phase runs as today and returns its full handoff
  text. Its prompt keeps the behavioral discipline (it still must invoke the
  `diagnose` skill) but sheds the artifact-format instructions and both worked
  examples — formatting is no longer its job.
- **Extract.** A second, cheap turn receives the diagnose output as its input and
  has one job: emit exactly one `<diagnosis-result>` tag containing a JSON object
  matching the schema, and nothing else. The tag wrapper is kept so the host can
  delimit the object even if the model adds a stray sentence; `json.loads` parses
  the inner object.
- **Same authority logic.** `diagnosis.py` keeps its classifier and issue-body
  authority grant unchanged in spirit — it parses a JSON object instead of
  key:value lines, then classifies `not-required` / `grant-ui-tests` /
  `out-of-scope` exactly as before.
- **Cheap, bounded recovery.** On bad JSON the host re-runs **only** the extraction
  turn, up to 2 retries (3 attempts total), then escalates for human attention. A
  formatting failure never re-runs the expensive reasoning.
- **Status is unchanged.** Phase completion still uses promise lines
  (`<promise phase="...">COMPLETE</promise>`); the diagnosis JSON is a *payload*,
  not a status signal. The completion mechanism is not touched.
- **Vocabulary.** "Extraction pass / extraction turn" is documented in
  `ralph/README.md`, not `CONTEXT.md` — this is orchestration tooling, not the
  workout-app product domain.

## Consequences

- The artifact is more robust: the extraction turn's sole task is clean output, so
  reasoning noise can no longer corrupt it. This is the only option of the three
  that genuinely raises robustness over today's parser.
- Each bug issue costs one extra short turn. Failure recovery is *cheaper* than
  today, because a malformed artifact re-runs only the extraction, never the
  reasoning.
- The design stays engine-agnostic: the extraction turn is an ordinary
  `run_phase` call with the prior output as its prompt, identical under `codex` and
  `claude`. No SDK session plumbing is introduced.
- `diagnose.md` shrinks substantially (the `<diagnosis_artifact_instructions>`
  block and both examples leave it), and a small `diagnose-extract` prompt is
  added. `diagnosis.py`'s public surface stays close to today's — it gains JSON
  parsing and loses the key:value field reader.
- This ADR does not change review, gates, publishing, or the promise-line
  contract; those are addressed (or deliberately left alone) in the accompanying
  prompt-layer spec.
