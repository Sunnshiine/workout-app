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
workflow pre-created `Secrets.xcconfig` from the template; no booted
simulator needed):

```bash
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
```

Do not run `WorkoutTrackerUITests` in this environment — they need a booted
simulator and are too slow for this run; UI-affecting changes still get a
human/Ralph pass locally.

# COMMIT

Make one or more git commits on `{{BRANCH}}`. Use conventional-commit messages (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`). Do NOT use a `RALPH:` prefix — that prefix is reserved for the Ralph loop.

Do not close the issue yourself.
