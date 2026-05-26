# CLAUDE.md

## Linting & Formatting

- **SwiftLint** runs automatically via the `SwiftLintPlugins` build tool plugin (added to `Package.swift`). Config: `.swiftlint.yml`.
- **swift-format** is installed via Homebrew. Config: `.swift-format`. Run manually: `swift-format -i -r WorkoutTracker/ WorkoutTrackerTests/`
- Do not run `swiftlint --fix` in build phases — run it manually when needed.
- When creating the Xcode project / `Package.swift`, add the SwiftLintPlugins dependency and apply the plugin to each target.