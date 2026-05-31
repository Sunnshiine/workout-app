# CLAUDE.md

A mobile client for powerlifting athletes that surfaces and logs workouts from a
coach-managed Google Sheet. The Sheet is the single source of truth; the app is a
read-write client with a local cache (ADR-0001).

> Generic Swift conventions (style, testing, patterns, security) are loaded automatically
> from `~/.claude/rules/swift/` — they are intentionally not duplicated here.

## Build, Test & Run

Scheme is `WorkoutTracker` for all runs; default simulator is `iPhone 17 Pro`.

```bash
# Fast unit + component tests (no Secrets.xcconfig needed)
swift test

# Unit + component tests via Xcode
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerTests

# UI integration tests
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerUITests

# Build & run on the simulator
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- The `WorkoutTracker` scheme launches with `-UITEST_FIXTURE true` and
  `-UITEST_SESSION true` — it runs against deterministic local fixtures, **not**
  the live Google Sheet. Ralph's `snapshot.sh` defaults to the seeded
  SessionView; set `UITEST_ARGS` for other fixture routes. To run against live
  data, use the `Copy of WorkoutTracker` scheme (`-UITEST_FIXTURE false`).
- Prefer XcodeBuildMCP for build/run/test on the simulator. If using XcodeBuildMCP,
  use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- If XcodeBuildMCP accessibility snapshots return an empty AXApplication, reboot
  the simulator before diagnosing app code.
- For target-specific UI gates, prefer raw `xcodebuild ... -only-testing:WorkoutTrackerUITests`
  or verify the output actually ran `WorkoutTrackerUITests`.

## Linting & Formatting

- **SwiftLint** runs automatically via the `SwiftLintPlugins` build tool plugin (added to `Package.swift`). Config: `.swiftlint.yml`.
- **swift-format** is installed via Homebrew. Config: `.swift-format`. Run manually: `swift-format -i -r WorkoutTracker/ WorkoutTrackerTests/`
- Do not run `swiftlint --fix` in build phases — run it manually when needed.

## Git Worktrees

When running `xcodebuild test` from a git worktree, copy `Secrets.xcconfig` from the project root first — it is git-ignored so worktrees don't get it automatically, and xcodebuild fails with a build error rather than a clear diagnostic. Ralph copies it automatically for issue and integration worktrees when a source file exists:

```bash
cp /Users/sunny/Projects/workout-app/Secrets.xcconfig ./Secrets.xcconfig
```

`swift test` does not require it; only `xcodebuild` does.

XcodeBuildMCP session defaults point at the main project path and do not apply inside a worktree. Pass `-project <worktree-path>/WorkoutTracker.xcodeproj` explicitly when calling xcodebuild from a worktree.

## Architecture

A navigation map; see `CONTEXT.md` for the domain glossary and `docs/adr/` for decisions.

```text
WorkoutTracker/
├── WorkoutTrackerApp.swift     App entry point (@main)
├── Models/                     Domain types (Block, Week, Session, Exercise, Set …)
├── Parsing/                    Sheet → domain interpretation (layout interpreter)
├── Sheets/                     Google Sheets client + auth (GoogleAuth.swift)
├── Stores/                     Local cache, sync coordination & persisted state
├── Progress/                   Session/Week progression (Current Session, Move On, Open Exercises, Supersets)
├── LoadSuggestionEngine.swift  Load Suggestion calculations
├── Theme.swift                 Liquid Glass design system (ADR-0004)
├── Views/                      SwiftUI views (excluded from the SPM library target)
└── Fixtures/                   UI-test fixture data (-UITEST_FIXTURE)

Tests/  →  Unit/ · Component/ · UI/ · Support/
```

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Sunnshiine/workout-app`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: read root `CONTEXT.md` for domain language and root `docs/adr/` for decisions. For product or UI work, also read `PRODUCT.md` and `DESIGN.md`. See `docs/agents/domain.md`.
