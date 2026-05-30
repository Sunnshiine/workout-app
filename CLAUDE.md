# CLAUDE.md

## Linting & Formatting

- **SwiftLint** runs automatically via the `SwiftLintPlugins` build tool plugin (added to `Package.swift`). Config: `.swiftlint.yml`.
- **swift-format** is installed via Homebrew. Config: `.swift-format`. Run manually: `swift-format -i -r WorkoutTracker/ WorkoutTrackerTests/`
- Do not run `swiftlint --fix` in build phases — run it manually when needed.
- When creating the Xcode project / `Package.swift`, add the SwiftLintPlugins dependency and apply the plugin to each target.

## Git Worktrees

When running `xcodebuild test` from a git worktree, copy `Secrets.xcconfig` from the project root first — it is git-ignored so worktrees don't get it automatically, and xcodebuild fails with a build error rather than a clear diagnostic:

```bash
cp /path/to/workout-app/Secrets.xcconfig ./Secrets.xcconfig
```

`swift test` does not require it; only `xcodebuild` does.

XcodeBuildMCP session defaults point at the main project path and do not apply inside a worktree. Pass `-project <worktree-path>/WorkoutTracker.xcodeproj` explicitly when calling xcodebuild from a worktree.

The scheme is `WorkoutTracker` for all test runs. Split unit and UI tests with `-only-testing`:

```bash
# Unit + component tests
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerTests

# UI integration tests
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerUITests
```

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Sunnshiine/workout-app`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: read root `CONTEXT.md` and root `docs/adr/`. See `docs/agents/domain.md`.
