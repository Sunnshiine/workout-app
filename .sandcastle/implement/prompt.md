# TASK

Implement issue #{{ISSUE_NUMBER}}: {{ISSUE_TITLE}}

You are on branch `{{BRANCH}}`, already created from `main`. Pull in the
issue with `gh issue view {{ISSUE_NUMBER}} --comments`. If it has a
parent PRD, pull that in too.

# CONTEXT

Read `CONTEXT.md` and any relevant ADRs under `docs/adr/` before
starting. For product or UI work, also read `PRODUCT.md` and
`DESIGN.md`. Explore the repo and fill your context with the parts
relevant to this issue — especially test files that touch the area
you'll change.

# EXECUTION

Use red-green-refactor where applicable.

1. RED: write one failing test
2. GREEN: implement to pass it
3. REPEAT until the issue is done
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

Make one or more git commits on `{{BRANCH}}`. Use conventional-commit messages (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).

Do not close the issue yourself.
