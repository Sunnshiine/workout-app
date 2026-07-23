# TASK

You are implementing one sub-issue of a multi-session PRD.

- **PRD:** #{{PRD_NUMBER}} — {{PRD_TITLE}}
- **This sub-issue:** #{{SUB_ISSUE_NUMBER}} — {{SUB_ISSUE_TITLE}}
- **Branch:** `{{BRANCH}}`

The branch may already have commits from earlier sub-issues. Do **not** rebase
or rewrite that history. Add your work on top.

Pull both issues in for context:

- `gh issue view {{PRD_NUMBER}} --comments` — the full PRD. Read this carefully; your implementation of this sub-issue must fit the larger plan.
- `gh issue view {{SUB_ISSUE_NUMBER}} --comments` — the specific step you are implementing now.

You also have access to the full list of sibling sub-issues:

`gh api repos/$GH_REPO/issues/{{PRD_NUMBER}}/sub_issues`

Use this to understand what work has already shipped on this branch and what
is still ahead — but **only implement #{{SUB_ISSUE_NUMBER}}** in this session.
Do not touch work that belongs to a different sub-issue.

# CONTEXT

Read `CONTEXT.md` and any relevant ADRs under `docs/adr/` before starting.
For product or UI work, also read `PRODUCT.md` and `DESIGN.md`. Explore the
repo and fill your context with the parts relevant to this sub-issue —
especially test files that touch the area you'll change.

# EXECUTION

Use red-green-refactor where applicable.

1. RED: write one failing test
2. GREEN: implement to pass it
3. REPEAT until the sub-issue is done
4. REFACTOR

Before committing, run `swift test` (fast unit + component tests; no
`Secrets.xcconfig` needed).

If your change touches the app target — anything under
`WorkoutTracker/Views/`, `WorkoutTrackerApp.swift`, or other code the SPM
library target doesn't compile — also compile-check the full app (the
workflow pre-created `Secrets.xcconfig` from the template):

```bash
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
```

# VISUAL VERIFICATION (mandatory for UI-touching changes)

If your change alters anything the user can see, read
`.sandcastle/VISUAL_LOOP.md` and complete both of its mechanisms before
committing: **record-and-look** (record the affected Visual Baselines, read
the PNGs against ground truth, commit them with the change) and
**eyes-on-app** (drive the fixture app through every screen you changed, both
appearances). The CI Visual Regression gate is the sole pass/fail authority.

Do not run `WorkoutTrackerUITests` in this environment — the sighted loop
above is the replacement (#469).

# COMMIT

Make one or more git commits on `{{BRANCH}}`. Use conventional-commit
messages (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).

Commit each completed, verified unit of work as soon as it is green rather
than accumulating one giant commit at the end: the runner has a hard time
ceiling, and everything **uncommitted** when it hits is lost. Committed work
survives — the workflow pushes the branch even when the run fails or is
cancelled, and the next run resumes from your last commit.

Two checkpoints are mandatory on UI-touching slices:

1. After `swift test` is green and **before** entering the visual loop,
   commit the code and unit/component tests. The recorded baselines join in
   a follow-up commit once they match the picks — a checkpoint whose visual
   work is unfinished is still a valid, resumable checkpoint.
2. The moment the recorded baselines first match the picks in both
   appearances, commit code + baselines **immediately** — before chasing
   flakes, stale PNGs, or any remaining stragglers. Slice 3 died 15 minutes
   from done with its solved work uncommitted; do not repeat that.

Include `Part of #{{PRD_NUMBER}}` in each commit body so the history is
linkable from the PRD. Do **not** include `Closes` in commits — closing the
sub-issue is the workflow's job, and closing the PRD is the merged PR's job.

Do not close the sub-issue yourself. Do not push the branch. The workflow
handles both.

# COMPLETION SIGNAL

When — and only when — the sub-issue is fully implemented, verified, and
committed, end your final message with this exact line:

`<promise>COMPLETE</promise>`

The runner treats the run as finished only when it sees this signal; a run
that ends without it is marked failed. Never emit it while any work is
outstanding — including a build or test run still in progress. If you end a
turn without the signal, the runner resumes your session to let you finish.
