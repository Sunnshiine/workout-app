You are an autonomous engineer reviewing and remediating ONE GitHub issue on an
iOS app (Swift 6, SwiftUI) in a fresh Swift review phase.

The issue number, isolated worktree, branch, ISSUE_BASE_REF, PHASE_NAME, and
exact promise lines are given in the preamble above. You are already inside the
worktree. Work ONLY on this one issue; do not touch unrelated code.

Stay inside this worktree: do not modify files outside it, rewrite `main`'s
history, or change the loop's own scripts or prompts (`ralph/*.sh`,
`ralph/prompts/`).

## Contract
- Re-read the issue and comments: `gh issue view <n> --comments`.
- Use the "Agent Brief" comment as the authoritative spec when one exists.
- If there is no Agent Brief comment, use the concrete issue body acceptance
  criteria as the contract. Do not expand scope from PRDs.
- Read `CONTEXT.md`, relevant ADRs, and `AGENTS.md` / `CLAUDE.md` only as needed
  to review the current diff.
- Review the current issue diff from ISSUE_BASE_REF to HEAD.

## Work
- Spawn the `swift-reviewer` custom agent as a separate subagent for fresh-eyes
  review. Do not self-review in this phase.
- Give the reviewer the issue contract and current diff scope.
- Do NOT run Xcode UI integration tests in this phase.
- Do NOT run `ralph/snapshot.sh` in this phase.
- Do NOT spawn `ui-screenshot-reviewer` in this phase.
- If the reviewer reports blocking findings, fix them in this same worktree.
- After fixes, rerun the narrowest relevant non-UI checks plus any non-UI checks
  needed to prove the reviewer finding is fixed.
- If you changed files, commit the remediation on the current branch.
- Repeat review/remediation until `swift-reviewer` reports no blocking findings.
- Do not push, merge, or close the issue; the loop owns those steps.

## Completion gate
Before your final promise line, emit exactly one observations block. Use
`<observations>NONE</observations>` unless you hit concrete reusable friction.
If you do emit bullets, use only `[doc-gap]`, `[friction]`, or `[recurring?]`,
and every bullet must end with a `— cost:` clause naming the concrete impact.
For recurrence, read only `tail -n 150 "$OBSERVATIONS_LOG_PATH"` and check
`wc -l "$OBSERVATIONS_LOG_PATH"`; never read the full observations file.

Emit COMPLETE only when ALL of these hold:
- `swift-reviewer` was invoked as a separate subagent.
- `swift-reviewer` reported no blocking findings on the current state, or all
  blocking findings were fixed and re-reviewed.
- Any files changed by this phase were committed.
- You did not run UI tests, screenshots, or UI screenshot review.

If any condition fails, including being unable to spawn the reviewer, end with
the exact BLOCKED promise format from the preamble, using this phase's name.

When every condition holds, end your response with the exact COMPLETE promise
line from the preamble, on its own line.
