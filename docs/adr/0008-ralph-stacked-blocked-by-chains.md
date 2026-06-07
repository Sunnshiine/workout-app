# ADR 0008: Ralph Stacks Blocked-by Chains onto an Accreting Root PR

**Status:** Accepted
**Date:** 2026-06-06

## Context

Issues frequently form a linear dependency chain — a feature sliced into ordered
steps, each declaring the previous one under `## Blocked by`. The Move On
Celebration F3 work is the motivating example: 221 → 222 → 223 → 224 → 225, each
`Blocked by` the one before it, none under a PRD.

The Python runner's selection and targeting actively defeat running such a chain
unattended:

- **Eligibility freezes behind human review.** `IssueSelector._dependency_landed`
  (`ralph/orchestrator/loop.py`) treats a dependency as satisfied only when it is
  `state == "CLOSED"`. A Ralph-authored PR is not closed until a human reviews and
  merges it — it sits at `agent-implemented`. So 222 never becomes eligible while
  221's PR is open, even though 221's work is finished and green. The chain
  freezes after a single issue.
- **No stacking.** `branch_for_contract` (`ralph/orchestrator/targets.py`) bases
  every one-off issue's branch on `main`. A follow-up that needs its predecessor's
  code cannot see it until that predecessor merges to `main`. There is no path for
  222 to build on 221's unmerged work.

The operating environment removes the usual reason to be conservative here: a
single Ralph loop runs at a time, one issue per iteration, so there is no
concurrent-rebase hazard and no mid-chain race. The work is fully serialized.

The alternatives considered were (a) **land-on-main** — keep requiring `CLOSED`
and merge each issue before its dependent runs (rejected: defeats unattended AFK
runs, the whole point of Ralph); and (b) a **stack of separate PRs**,
Graphite-style, each based on the previous branch (rejected: 5× the review
surface and rebase cascades for a chain the human wants to review as one cohesive
feature).

## Decision

A `Blocked by` chain runs as a single **accreting root PR**. The transitive root
of the chain owns the one durable branch; every dependent stacks onto it and
squashes back into it.

- **Base resolution = chain root.** A dependent's base is resolved by walking
  `## Blocked by` upward to the eldest ancestor whose own blocker is `None` or
  already merged to `main`. That ancestor's `ralph/issue-<n>` branch is the
  durable, accreting **root branch**. For 221–225 the root is always
  `ralph/issue-221` — not `main`, and not a predecessor's discarded scratch
  branch. A dependent is built in a scratch worktree based on the root branch.
- **Eligibility keyed on label, not closure.** A dependency is satisfied when it
  is `agent-implemented` **or** `CLOSED` — both mean its work is on the root
  branch. `agent-implemented` is only ever applied after gates pass and the squash
  lands, so it already implies "green and on the root"; no separate gate check is
  needed. `agent-active`/`ready-for-agent` mean "not landed yet," so the dependent
  waits.
- **Success squashes onto the root.** When a dependent's gates pass, its work is
  squashed into one commit on the root branch, and a `Closes #<n>` line is appended
  to the root PR body. The root PR accretes one commit and one `Closes` line per
  issue.
- **Failure splits to a rescue PR.** A blocked issue is published to
  `ralph/issue-<n>-blocked` so its work is preserved. Because its work never landed
  on the root, every transitive dependent of it is permanently ineligible:
  `agent-blocked` **halts the chain** at that link.
- **Human merge closes the chain.** The reviewer reviews and merges the single root
  PR (`ralph/issue-221 → main`); that one merge closes every issue named in its
  accumulated `Closes` lines. "Closed" continues to mean "human-reviewed and
  merged."
- **Vocabulary.** "Root branch / root PR" (the accreting durable branch), "scratch
  branch" (a dependent's ephemeral worktree, discarded after squash), "chain"
  (a transitive `Blocked by` lineage), "rescue PR" (existing). Documented in
  `ralph/README.md`, not `CONTEXT.md` — this is orchestration tooling, not the
  workout-app product domain.

## Consequences

- The AFK loop runs an entire dependency chain unattended, with no mid-chain human
  merge required. This is the behavior the chain authoring already implied.
- No work is lost on failure: the rescue PR preserves a blocked issue's progress,
  and the chain cleanly halts rather than building dependents on absent code.
- The root PR grows large before a human looks at it, and per-issue review and
  single-issue revert granularity are lost — a deliberate trade for chain velocity.
  Reviewers read the chain as one cohesive feature.
- Two core invariants are inverted and must change: `select_next` eligibility
  (`agent-implemented` now satisfies a dependency) and `branch_for_contract` /
  target resolution (a dependent bases on the chain root, not `main`).
  Blocked-link halt propagation is new logic. `targets.py`'s rejection of any
  non-`main` base no longer holds for stacked dependents.
- The single-loop, one-issue-at-a-time assumption is load-bearing. Concurrent Ralph
  loops over the same chain would reintroduce the rebase hazard this ADR assumes
  away and would need revisiting before that is allowed.
