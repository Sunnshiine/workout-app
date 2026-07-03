# TASK

You are running the scheduled architecture-review pass. Find **one** fresh
deepening opportunity in this codebase and propose it as a PRD.

This is an unattended CI run. There is no user to grill, no HTML report to
write, and you are **read-only** — the wrapping workflow publishes the issue
from your structured output. Your job is:

1. List prior proposals labelled `source:architecture-review` (open and
   closed) so you don't re-propose them:
   `gh issue list --state all --label "source:architecture-review" --limit 100 --json number,title,state`
2. Explore the codebase.
3. Pick **one** top candidate.
4. Emit it as a `proposed` output (or `skipped` if nothing fresh remains).

# METHODOLOGY

Look for **deepening** opportunities — places where the module boundary is
shallower than the domain it serves:

- **Deletion test:** if a file or abstraction were deleted, would anything of
  value be lost, or would the code get simpler? Pass-through layers, shallow
  wrappers, and one-caller indirections are candidates for removal PRDs.
- **Deep modules:** interfaces that force callers to know internals (many
  parameters, ordered call sequences, leaked types) are candidates for a
  deepening PRD — small interface, deep implementation.
- **Glossary drift:** code whose names diverge from the domain glossary in
  `CONTEXT.md` (Block, Week, Session, Exercise, Set, Move On, Load
  Suggestion, …). Renaming/realigning PRDs are valid candidates.
- **Duplication of decision-making:** the same domain rule interpreted in
  more than one place (e.g. parsing vs. progress logic) is a candidate for
  consolidation.

**Loose-duplicate rule:** a candidate is stale if any prior
`source:architecture-review` issue covers substantially the same ground —
even with different wording, and even if that issue was closed as wontfix.
Skip stale candidates.

# PRD SHAPE

The `body` you emit must read like a PRD the `agent:to-issues` workflow can
slice later:

- **Problem** — what is shallow/drifted/duplicated today, with file paths.
- **Proposal** — the target end state, in domain vocabulary.
- **Non-goals** — what this PRD explicitly does not change.
- **Risks** — behaviour that must be preserved, and how tests protect it.

# CONTEXT

Read `CONTEXT.md` and any relevant ADRs under `docs/adr/` before proposing
anything. Treat ADRs as binding — do not propose changes that contradict a
recorded decision.

# RULES

- Read-only on the repo. No commits. No edits to `CONTEXT.md`, ADRs, or
  source files. No issue creation — the workflow publishes from your output.
- One PRD per run. If every reasonable candidate is already covered by a
  prior `source:architecture-review` proposal, emit a `skipped` output and
  stop.
- No questions to a user — there is none. Make the call.
