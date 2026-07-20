# Testing

## AI-Generated Code Gate

The acceptance gate prioritizes behavior correctness first. Simulator user-flow tests protect the
small number of workflows where app wiring matters. Visual Regression tests protect known-good
pixels for covered surfaces.

Layer duties:

- `swift test` proves domain and module behavior through public interfaces with realistic inputs.
- Component tests prove SwiftUI component state contracts at unit-test speed, without rendering
  pixels.
- `xcodebuild test` proves the app target compiles and simulator-hosted tests run.
- Visual Regression tests prove rendered screens match committed Visual Baselines.
- UI tests prove critical user flows through real controls.

Component tests are not full app launches. They do not touch Google auth, the network, or complete
navigation flows. They cover view-facing labels, accessibility strings, enabled states, form state,
and progression state. Visual Regression tests are the separate pixel layer; do not use component
tests to assert screenshots.

Visual vocabulary:

- **Visual Regression test**: a hosted unit test under `Tests/Visual` that renders a deterministic
  SwiftUI view and compares it to a committed reference image.
- **Visual Baseline**: the committed PNG under `Tests/Visual/__Snapshots__` that defines the
  known-good pixels for one Visual Regression test.

Visual tests use `swift-snapshot-testing` as a test-only dependency. Recording is disabled by
default, so a missing or changed Visual Baseline fails instead of silently re-recording. New or
intentional baseline changes must be recorded deliberately. Ralph does not add a model-review or
special-authorization layer on top of the programmatic Visual Regression tests.
The shared Visual trait configuration is pinned to iPhone 17 Pro on the iOS 27.0 runtime (the
CI runner's preinstalled runtime — the pin moves with the runner image, see ADR-0007), light
mode, `en_US`, fixed default Dynamic Type, and exact precision (`1.0`).

Recording recipe (issue #471): the recording switch is the suite trait, not an environment
variable — `SNAPSHOT_TESTING_RECORD` is overridden by the explicit trait and does nothing here.
To record: flip the affected suite's `@Suite(.snapshots(record: .never))` to
`.snapshots(record: .all)` in `Tests/Visual/*.swift`, run the Visual suite
(`xcodebuild test … -only-testing:WorkoutTrackerSnapshotTests` on the pinned destination), then
revert the trait to `.never` before committing. Two caveats: a record run that crashes leaves
the stale PNG silently in place, and the CI runner is the canonical recorder — baselines
recorded on other machines differ at exact precision (issue #479). CI agents record on the
runner itself; humans recording locally should expect the `visual-tests` job to re-arbitrate.

Initial component-test scope:

- `ActiveSetPresentation`: pending, logged/checkmark, bodyweight, and drop-percent suggestion
  states.
- `SmartValuePillsForm`: empty/disabled, valid log preview, and selected RPE states.
- `SessionProgressHeaderPresentation`: mixed Session progress with the Current Session highlighted.
- `BlockOverview` presentation state: the 4x4 Session grid with representative Session states.
- `SyncStatusBanner` presentation state: syncing, queued writes, and failed states.

Target directory structure:

- `Tests/Unit`: domain, parser, store, persistence, sync, and write-path tests. Runs in the
  existing fast `WorkoutTrackerTests` target.
- `Tests/Component`: SwiftUI component state-contract tests that still run at unit-test speed.
  Runs in the existing fast `WorkoutTrackerTests` target.
- `Tests/Visual`: hosted Visual Regression tests plus Visual Baselines. Runs in the
  `WorkoutTrackerSnapshotTests` target via xcodebuild, not `swift test`.
- `Tests/UI`: simulator XCUITest coverage that launches the app and drives real controls.
  Uses a separate Xcode UI-test target, split by purpose into UI Integration Smoke and the
  UI Interaction Suite.

Migration policy: move the existing flat `WorkoutTrackerTests` files into this structure in one
mechanical change before adding new coverage. Update `Package.swift`, `project.yml`, regenerate the
Xcode project, and verify with `swift test` plus `xcodebuild test` immediately after the move.

Test doubles policy:

- `Tests/Unit` may use pure fixtures and protocol stubs at true I/O boundaries only: Sheets client,
  auth/defaults, and SwiftData in-memory containers.
- `Tests/Component` may use deterministic domain objects and presentation-state builders. It should
  assert component state contracts, not fake complete app flows.
- `Tests/UI` launches the real app with deterministic fixture mode, fakes external services at
  launch boundaries, and drives real controls through accessibility.
- Automated tests must not hit live Google auth, live Google Sheets, or real network connectivity.

UI XCUITest boundary:

- UI Integration Smoke is the real-control wiring layer. It proves launch state, navigation, accessibility
  lookup, hittability, route completion, and one representative end-to-end flow per critical app
  surface.
- The UI Interaction Suite covers higher-flake interaction mechanics such as keyboard focus,
  overscroll, long scrolling, hold gestures, and frame/visibility behavior. It is a manual,
  nightly, or pre-release suite, not part of Ralph's autonomous loop.
- UI XCUITests may assert that a real user action reaches a visible result. Unit and component tests own
  the detailed state rules, permutations, string construction, persistence semantics, and business
  logic behind that result.
- UI XCUITests may include layout assertions only when the assertion protects functional accessibility:
  a control must remain tappable, readable, reachable, and not clipped out of usable bounds. Pixel
  polish, spacing, exact frame relationships, and broad appearance coverage belong to Visual
  Regression tests or component/presentation tests.
- Gesture-heavy surfaces should keep at most one representative UI gesture per critical path to
  prove the real SwiftUI attachment works. Component or unit tests own thresholds, timing, idle
  behavior, precommit releases, and state-machine edge cases.
- Settings and Developer Tools should have route smokes plus one representative critical
  confirmation path. Store, sync, reset, diagnostics, and pending-write rules belong to lower-level
  tests unless the app-layer wiring itself is the risk.
- UI cleanup issues must identify the replacement coverage owner before deleting or narrowing an
  XCTest. Either cite existing unit, component, visual, or Ralph coverage, or add the missing
  lower-level coverage first.
- Pruning UI tests does not authorize agents to skip replacement coverage. UI Integration Smoke may
  run inside Ralph only when a mechanical selector limits the run to the stable smoke subset.
  Otherwise, run UI XCUITests by a human, dedicated script, or explicit non-Ralph CI/manual gate when
  UI confidence is required.
- Mechanically isolate UI Integration Smoke with dedicated test classes inside the existing
  `WorkoutTrackerUITests` target. Ralph must invoke those classes by class-level `-only-testing`
  selectors, not by targeting the whole `WorkoutTrackerUITests` bundle.

Smoke selector command:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

Manual or non-Ralph UI Interaction Suite command:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerInteractionUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerAppearanceUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerLongSessionUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerSkipUITests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUITests
```

Shared fixture policy:

- Put shared builders and named scenarios under `Tests/Support`.
- Reuse the same canonical scenarios across layers, with layer-specific assertions.
- Initial scenarios: fresh configured app, Current Session with Pending Sets, partially Logged
  Session, Open Exercises, sync failure, queued write, and Block Overview with mixed Session states.
- UI launch fixtures should stay small and named. Add a new UI fixture route only when it protects a
  distinct app-layer wiring risk that cannot be reached from the existing shared scenarios without
  making the test substantially broader.

Per-change test selection:

- Parser, write-path, progression, persistence, and store changes require unit tests.
- View-facing labels, enabled states, accessibility text, and active-card state changes require
  component tests.
- Known visual surface changes require the relevant Visual Regression tests to pass with recording
  disabled.
- Navigation, launch state, real control interaction, and cross-store workflows require UI
  integration tests.
- Pure visual restyling requires relevant Visual Regression coverage when the surface has a
  baseline. Component or UI tests are required only when behavior or state contracts change.

UI-test frame assertions:

- Accessibility frames are hit targets, not visual bounds. Do not treat a native 44 pt hit target
  intersecting a compact visual element's layout frame as proof of a visual collision. For compact
  header controls such as the Current Session Settings gear, prefer assertions that prove the
  control exists, is hittable, remains separated from real neighboring controls/cards, and opens the
  intended surface. Use Visual Regression tests or human review for actual visual-overlap questions.

Agent gate policy:

- During implementation, agents should run the narrowest relevant tests for the layer being changed.
- Ralph may run UI Integration Smoke only after it is mechanically isolated from the rest of
  `WorkoutTrackerUITests`. Ralph must not run the full UI target or the UI Interaction Suite. If no
  smoke-only selector exists, Ralph's autonomous issue loop is non-UI.
- Before an issue is complete or merged outside Ralph, it must pass the relevant automated testing framework:
  `swift test`, `xcodebuild test` for unit/component tests, `xcodebuild test` for Visual Regression
  tests when applicable, UI Integration Smoke when mechanically selected, explicit UI Interaction
  Suite runs when higher-flake interaction confidence is required, and `swiftlint lint --quiet`.
- Ralph's README, prompts, and gate script must keep this boundary mechanical so autonomous issues
  cannot silently run the full UI target or the UI Interaction Suite during the loop.

Implementation slices:

1. Mechanical structure migration: move the existing tests, update project configuration, regenerate
   Xcode, and verify the current suite still passes.
2. Component/state-contract expansion: add missing component tests using shared `Tests/Support`
   builders.
3. UI integration target: add `Tests/UI` and cover the agreed fixture-driven user flows.
4. Fixture unification: promote ad hoc fixtures and the launch fixture into named shared scenarios.
5. Ralph gate update: run the non-UI framework plus mechanically isolated UI Integration Smoke
   before autonomous issues can publish, and leave the UI Interaction Suite to an explicit
   human/manual or non-Ralph gate.

Representative UI Integration Smoke scope:

- Launch the deterministic Current Session fixture, select RPE, log the first Set, and verify the
  next active Set advances.
- Move On from a deterministic completed or ready-to-advance Session, dismiss the Move On
  Celebration, and verify the next intended Session or Exercise appears.
- Open Block Overview, switch to a non-current Session, verify Make Current / Go Back controls, and
  return to the Current Session.
- Open Settings from a deterministic route and exercise one representative pending-write sign-out
  confirmation path.
- Open a Partially Uploaded Block, verify one Unavailable Session is inert, and verify one Available
  Session still opens.

Do not promote a broad chained journey into Ralph smoke. Split it into these short named flows first,
and leave keyboard focus, overscroll, long-session scrolling, hold gestures, exact frame movement,
and celebration visibility-ratio checks in the UI Interaction Suite.

# Manual Testing on the iOS Simulator

## Prerequisites

- **Xcode 26.3** — required for the iOS 26.0 deployment target
- **iOS 26.3.1 simulator runtime** — should already be installed; check via
  Xcode → Settings → Platforms if the app fails to launch

## Running the App

1. Open `WorkoutTracker.xcodeproj` in Xcode
2. Select the **WorkoutTracker** scheme (top bar, left of the device picker)
3. Choose a simulator — **iPhone 17 Pro** is a good default

   > Available devices: iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air, iPhone 16e.
   > "iPhone 16" does not exist in the iOS 26.3.1 runtime — don't use it.

4. Press **Cmd+R** to build and run

Build time is ~30–60 s on first run (Swift packages resolve). Subsequent builds are fast.

## First-Run Onboarding

The app opens to **OnboardingView** on a fresh install (no sign-in, no sheet configured):

1. **Sign in with Google** — tap the button; a Safari sheet opens for OAuth. Use your Google account that has read access to the training sheet.
2. Once signed in, a text field appears — **paste the full Google Sheet URL** (e.g. `https://docs.google.com/spreadsheets/d/<ID>/edit`).
3. Tap **Save**. The app validates the URL and extracts the sheet ID. A bad URL shows an inline error.
4. On success the app navigates to **SessionView**.

## What This Branch Has (plan-1/read-only-viewer)

- Onboarding flow (sign in + sheet URL)
- `SyncCoordinator` — fetches the sheet from the Sheets REST API, parses it, and persists the Block to SwiftData
- `WorkoutStore` — loads the Block and derives the current Session
- `SessionView` — displays the current Session read-only (exercises and sets, no logging yet)

## Resetting State

To start fresh (re-trigger onboarding):

- **Delete the app** from the simulator home screen → reinstall via Cmd+R

Or from the Xcode menu: **Product → Scheme → Edit Scheme → Arguments** and add a launch argument to clear defaults on boot — or just delete and reinstall, it's faster.

## Running via xcodebuild (no Xcode GUI)

```bash
xcodebuild -project WorkoutTracker.xcodeproj \
  -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

To boot and install without Xcode:

```bash
# Boot the simulator
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator

# Build + install
xcodebuild -project WorkoutTracker.xcodeproj \
  -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build

# The .app path is in DerivedData — easier to just use Cmd+R in Xcode
```
