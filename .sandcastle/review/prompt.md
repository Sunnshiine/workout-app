# TASK

Review PR #{{PR_NUMBER}} on branch `{{BRANCH}}` for issue #{{ISSUE_NUMBER}}: {{ISSUE_TITLE}}

You are an expert code reviewer. Your job is **not just to comment** — actively improve the code on this branch, and explain what you changed.

# CONTEXT

Read `CONTEXT.md`, `.sandcastle/CODING_STANDARDS.md`, and any relevant ADRs under `docs/adr/` before starting. For UI work, `DESIGN.md` records the design system (Liquid Glass, ADR-0004).

<linked-issue>

{{LINKED_ISSUE}}

</linked-issue>

<diff-to-main>

!`git diff main..HEAD`

</diff-to-main>

<pr-comments>

The following PR comments have been fetched by the workflow. They are tagged by surface:

- `issue_comment` — top-level PR conversation comment, not anchored to code.
- `review_thread` — inline thread anchored to a file + line. Only **unresolved** threads are included. Each has a `commentId` you can reply to in-thread.
- `review_summary` — top-level body of a submitted review (with approve/request-changes/comment state).

```json
{{PR_COMMENTS_JSON}}
```

</pr-comments>

# REVIEW PROCESS

## 1. Analyse with the `code-review` skill

Use the **`code-review` skill** (installed globally at `~/.claude/skills/code-review`) to produce the review. It analyses the diff along two axes — **Standards** and **Spec** — using parallel sub-agents. Its findings are the **single source of truth** for what's wrong with this branch: act only on what it reports, not on a separate ad-hoc pass of your own.

Invoke it with everything it needs, so it does **not** run its own discovery and does **not** prompt or pause:

- **Fixed point:** `main`. The diff to review is `git diff main...HEAD`. Do not ask for a fixed point — it is `main`.
- **Spec:** the linked issue, fetched above in `<linked-issue>`. Pass this as the spec. If there is no linked issue, the PR description is the spec. If the linked issue is a **PRD** (it has sub-issues), pull them with `gh api repos/$GH_REPO/issues/<issue-number>/sub_issues` and treat each closed sub-issue as a sub-requirement; code for an _open_ sub-issue is a scope violation.
- **Standards:** `.sandcastle/CODING_STANDARDS.md` is this repo's documented standard — feed it as the standards source. The skill's built-in smell baseline applies on top, but a documented repo standard always wins.

The skill is read-only and produces a report; it does not edit code. That report — its Standards findings and its Spec findings — is your worklist for the steps below.

## 2. Look at the pixels (artifact eyes)

If the diff touches anything the user can see (`WorkoutTracker/Views/`, `Theme.swift`, `Tests/Visual/`), verify the branch with your eyes — a gate only catches drift from committed baselines; a sighted reviewer catches baselines that are wrong or missing (that is how PR #467 shipped):

- `Read` every Visual Baseline PNG added or changed under `Tests/Visual/__Snapshots__/` in this diff and compare it against the ground truth: `docs/design/greenhouse-picks/` (its `README.md` maps screen → pick → DESIGN.md section; DESIGN.md wins over pixels).
- If the diff touches a redesigned surface but records **no** baseline for it — or deletes baselines without replacements — treat that as a spec finding: call it out in the summary and inline comments.
- If the CI `visual-tests` job is red on this PR, read its uploaded snapshot-diff artifacts to see *why* before commenting.
- The XcodeBuildMCP tools (`.sandcastle/VISUAL_LOOP.md`, mechanism 2) are available at your discretion if you need to see a screen in motion; they are not a mandatory review duty.

## 3. Act on the skill's findings

Work through the skill's findings and resolve each one on this branch:

- For any **correctness/robustness** finding, write a test that exercises it and try to actually break it. If you can break it, fix it. Cover the edge cases the skill flagged (empty/zero/negative inputs, missing optional values, nil handling, off-by-one, races, regressions in adjacent code).
- For any **quality/standards** finding, improve the code: reduce nesting, eliminate redundancy, improve names, consolidate related logic, drop comments that restate obvious code, choose clarity over brevity. Apply `.sandcastle/CODING_STANDARDS.md`.
- For any **spec** finding (missing coverage, scope creep, misinterpretation), do **not** silently "fix" missing spec coverage by adding code yourself — call it out in the `summary` and (where line-anchored) the inline comments for the human reviewer to decide.

**Preserve functionality.** When improving code, never change what it does — only how it does it. All original features, outputs, and behaviours must remain intact.

# RESPONDING TO HUMAN COMMENTS

For each unresolved `review_thread` and each `issue_comment` directed at the code, choose one:

- **Address** — make a code change in your commit, then reply in-thread (or with an issue comment) explaining what you did. Use the comment's `commentId` for in-thread replies.
- **Decline** — don't change the code, but reply explaining your reasoning. Use Decline when you have a substantive disagreement (the suggestion would break something, conflicts with project standards, is out of scope).
- **Defer** — do nothing, no reply. Only valid when the comment isn't a code-review request (jokes, off-topic banter, stale comments about already-fixed code, side conversations between humans).

Default to Address. Decline when you have a real reason. Defer only when a reply would be noise.

# EXECUTION

1. Run `swift test` — confirm the current state passes.
2. Make improvements + write any new edge-case tests. Stage and commit them as a **single squashed commit** on this branch with a message starting with `refactor(review):` (or `fix(review):` / `test(review):` if that better describes the change).
3. Run `swift test` again. If it fails, fix it before continuing — do not leave the branch broken. If the branch (or your improvements) touch the app target — anything under `WorkoutTracker/Views/`, `WorkoutTrackerApp.swift`, or other code the SPM library target doesn't compile — also compile-check it before finishing (the workflow pre-created `Secrets.xcconfig` from the template; no booted simulator needed): `xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO`. This environment has Xcode 26, so Views code (Liquid Glass APIs) is fully verifiable — do not decline a Views-touching improvement on the grounds that it can't be compile-checked here.
4. Decide which inline review comments to leave (line-anchored notes about your changes or remaining findings) and which thread replies to make.

If the code is already clean and there are no human comments to address, make no commits.
