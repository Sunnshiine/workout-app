# WorkoutTracker

A mobile client for powerlifting athletes that surfaces and logs workouts from a
coach-managed Google Sheet. The Sheet is the single source of truth; the app is a
read-write client with a local cache.

## Getting started

Requirements:

- Xcode 26 or newer
- iPhone 17 Pro simulator runtime
- Swift Package Manager dependencies resolved by Xcode or `swift test`

Open `WorkoutTracker.xcodeproj` in Xcode and run the `WorkoutTracker` scheme on
the iPhone 17 Pro simulator. That scheme launches against deterministic local
fixtures, not live Google Sheets data.

```bash
swift test   # fast unit + component tests, no Secrets.xcconfig needed
```

To build the app target against Google Sign-In configuration, copy the template
and provide your own iOS OAuth client values:

```bash
cp Secrets.xcconfig.template Secrets.xcconfig
```

`Secrets.xcconfig` is ignored by git. Do not commit real OAuth client values,
tokens, spreadsheet IDs, or private athlete data.

## Google Sheets setup

The app reads and writes workouts from a Google Sheet selected by the signed-in
user. Public builds must provide their own Google Cloud OAuth client configured
for iOS and the bundle ID in `project.yml`.

The default `WorkoutTracker` scheme is fixture-backed for deterministic testing.
Use the `Copy of WorkoutTracker` scheme only when you intentionally want to run
against live Google account data.

## Tests

```bash
# Fast unit and component tests
swift test

# Xcode unit/component tests
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerTests

# UI integration tests
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerUITests
```

## TestFlight

Release uploads are scripted in `scripts/upload-testflight.sh`. See
`docs/TESTFLIGHT.md` for the App Store Connect setup, signing assumptions, and
the upload command.

## Docs

- **`AGENTS.md`** / **`CLAUDE.md`** — build, test, and contribution guide for AI agents
- **`CONTEXT.md`** — domain glossary (Block, Session, Set Log, Load Suggestion …)
- **`PRODUCT.md`** — product purpose, user context, brand personality, and anti-references
- **`DESIGN.md`** — design system, visual rules, and component guidance
- **`docs/adr/`** — architecture decision records

## License

MIT. See `LICENSE`.
