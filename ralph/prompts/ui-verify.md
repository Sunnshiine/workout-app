You are an autonomous engineer verifying ONE GitHub issue on an iOS app
(Swift 6, SwiftUI) in a fresh UI verification phase.

The issue number, isolated worktree, branch, ISSUE_BASE_REF, publish target,
UI_SHOT_PATH, UI_REVIEW_PATH, PHASE_NAME, and exact promise lines are given in
the preamble above. You are already inside the worktree. Work ONLY on this one
issue; do not touch unrelated code.

Stay inside this worktree: do not modify files outside it, rewrite `main`'s
history, or change the loop's own scripts or prompts (`ralph/*.sh`,
`ralph/prompts/`). Writing review artifacts under `ralph/.artifacts/` is
expected.

## Contract
- Re-read the issue and comments: `gh issue view <n> --comments`.
- Use the "Agent Brief" comment as the authoritative spec when one exists.
- If there is no Agent Brief comment, use the concrete issue body acceptance
  criteria as the contract. Do not expand scope from PRDs.
- Read related PRD/spec context if it helps evaluate the issue, but never let
  PRDs/specs override or expand the issue contract.
- Read `CONTEXT.md`, relevant ADRs, and `AGENTS.md` / `CLAUDE.md` only as needed
  to verify UI behavior.
- If the issue has a Branch Directive, honor it as publication context. Do not
  push, merge, open a PR, close a PR, or close the issue yourself.

## Work
- Run Xcode UI integration tests for `WorkoutTrackerUITests`.
- Do NOT spawn `swift-reviewer` in this phase.
- If the UI tests fail because of the issue implementation, fix the failure in
  this same worktree and rerun the relevant UI tests.
- If the UI tests fail because of simulator/tooling infrastructure that you
  cannot remediate inside this issue, report BLOCKED with the phase-specific
  promise line.
- If `git diff --name-only "$ISSUE_BASE_REF" HEAD -- WorkoutTracker/Views/ WorkoutTracker/Theme.swift`
  returns any paths, capture a screenshot with:
  `PROJECT_DIR="$PWD" ralph/snapshot.sh "<UI_SHOT_PATH>"`
- For View/Theme changes, spawn the `ui-screenshot-reviewer` custom agent as a
  separate subagent with the issue contract and screenshot, then save its exact
  output to `UI_REVIEW_PATH`.
- Treat any blocking UI screenshot finding as unfinished work: fix it in this
  worktree, re-capture the screenshot, and request UI screenshot review again.
- Inspect Visual Baseline changes with:
  `git diff --name-status "$ISSUE_BASE_REF" HEAD -- Tests/Visual/__Snapshots__`
- Added Visual Baselines (`A`) need no baseline-diff review in this phase.
- Deleted Visual Baselines (`D`) cannot be approved autonomously; report BLOCKED.
- For every modified Visual Baseline (`M`), create a review bundle under
  `ralph/.artifacts/visual-baseline-reviews/` using this exact naming contract:
  - `digest="$(printf '%s' "$baseline_path" | shasum -a 256 | awk '{print $1}')"`
  - old image: `ralph/.artifacts/visual-baseline-reviews/$digest-old.png`
  - new image: `ralph/.artifacts/visual-baseline-reviews/$digest-new.png`
  - diff image: `ralph/.artifacts/visual-baseline-reviews/$digest-diff.png`
  - review markdown: `ralph/.artifacts/visual-baseline-reviews/$digest.md`
- Build the modified-baseline review bundle with:
  - `mkdir -p ralph/.artifacts/visual-baseline-reviews`
  - `git show "$ISSUE_BASE_REF:$baseline_path" > "ralph/.artifacts/visual-baseline-reviews/$digest-old.png"`
  - `cp "$baseline_path" "ralph/.artifacts/visual-baseline-reviews/$digest-new.png"`
  - `swift ralph/visual-baseline-diff.swift "ralph/.artifacts/visual-baseline-reviews/$digest-old.png" "ralph/.artifacts/visual-baseline-reviews/$digest-new.png" "ralph/.artifacts/visual-baseline-reviews/$digest-diff.png"`
- For each modified baseline, spawn the `ui-screenshot-reviewer` custom agent as a
  separate subagent in baseline-diff mode. Give it the issue contract, baseline
  path, old image path, new image path, and diff image path, and ask it to answer
  whether every changed pixel is explained by the issue acceptance criteria. Save
  its exact output to the matching `$digest.md` review markdown path.
- Treat any blocking baseline-diff finding as unfinished work: either fix the code
  so the baseline diff returns to zero, or report BLOCKED if the intended baseline
  change requires human judgement.
- If you changed files, commit the UI remediation on the current branch.
- Do not push, merge, or close the issue; the loop owns those steps.

## Completion gate
Before your final promise line, emit exactly one observations block. Use
`<observations>NONE</observations>` unless you hit concrete reusable friction.
If you do emit bullets, use only `[doc-gap]`, `[friction]`, or `[recurring?]`,
and every bullet must end with a `— cost:` clause naming the concrete impact.
For recurrence, read only `tail -n 150 "$OBSERVATIONS_LOG_PATH"` and check
`wc -l "$OBSERVATIONS_LOG_PATH"`; never read the full observations file.

Emit COMPLETE only when ALL of these hold:
- Xcode UI integration tests passed.
- For View/Theme changes, the screenshot exists and the saved UI review
  artifact's last line is exactly:
  `PASS: no blocking static visual findings.`
- Every modified Visual Baseline has a saved baseline-diff review artifact under
  `ralph/.artifacts/visual-baseline-reviews/` whose last line is exactly:
  `PASS: no blocking static visual findings.`
- No Visual Baseline was deleted.
- Any files changed by this phase were committed.
- You did not run Swift review.

If any condition fails, end with the exact BLOCKED promise format from the
preamble, using this phase's name.

When every condition holds, end your response with the exact COMPLETE promise
line from the preamble, on its own line.
