# Testing

## AI-Generated Code Gate

The acceptance gate prioritizes behavior correctness first. Simulator user-flow tests protect the
small number of workflows where app wiring matters. Visual Regression tests protect known-good
pixels, while static screenshot checks still protect obvious View and Theme regressions.

Layer duties:

- `swift test` proves domain and module behavior through public interfaces with realistic inputs.
- Component tests prove SwiftUI component state contracts at unit-test speed, without rendering
  pixels.
- `xcodebuild test` proves the app target compiles and simulator-hosted tests run.
- Visual Regression tests prove rendered screens match committed Visual Baselines.
- UI tests prove critical user flows through real controls.
- Ralph screenshots prove static rendering did not obviously break; they are not behavior tests.

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
intentional baseline changes must be recorded deliberately and reviewed as changed artifacts.
The shared Visual trait configuration is pinned to iPhone 17 Pro on the iOS 26.3.1 runtime, light
mode, `en_US`, fixed default Dynamic Type, and exact precision (`1.0`).

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
- `Tests/UI`: simulator UI integration tests that launch the app and drive real controls.
  Uses a separate Xcode UI-test target.

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

UI integration test boundary:

- `Tests/UI` is the real-control wiring layer. It proves launch state, navigation, accessibility
  lookup, hittability, route completion, and one representative end-to-end flow per critical app
  surface.
- UI tests may assert that a real user action reaches a visible result. Unit and component tests own
  the detailed state rules, permutations, string construction, persistence semantics, and business
  logic behind that result.
- UI tests may include layout assertions only when the assertion protects functional accessibility:
  a control must remain tappable, readable, reachable, and not clipped out of usable bounds. Pixel
  polish, spacing, exact frame relationships, and broad appearance coverage belong to Visual
  Regression tests, Ralph screenshots, or component/presentation tests.
- Gesture-heavy surfaces should keep at most one representative UI gesture per critical path to
  prove the real SwiftUI attachment works. Component or unit tests own thresholds, timing, idle
  behavior, precommit releases, and state-machine edge cases.
- Settings and Developer Tools should have route smokes plus one representative critical
  confirmation path. Store, sync, reset, diagnostics, and pending-write rules belong to lower-level
  tests unless the app-layer wiring itself is the risk.
- UI cleanup issues must identify the replacement coverage owner before deleting or narrowing an
  XCTest. Either cite existing unit, component, visual, or Ralph coverage, or add the missing
  lower-level coverage first.
- Pruning UI tests does not change the completion gate. The remaining representative UI suite still
  runs before an issue is complete or merged.

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
- Pure visual restyling requires Ralph screenshot verification. Component or UI tests are required
  only when behavior or state contracts change.

UI-test frame assertions:

- Accessibility frames are hit targets, not visual bounds. Do not treat a native 44 pt hit target
  intersecting a compact visual element's layout frame as proof of a visual collision. For compact
  header controls such as the Current Session Settings gear, prefer assertions that prove the
  control exists, is hittable, remains separated from real neighboring controls/cards, and opens the
  intended surface. Use screenshots, Visual Regression tests, or Ralph screenshot review for actual
  visual-overlap questions.

Agent gate policy:

- During implementation, agents should run the narrowest relevant tests for the layer being changed.
- Before an issue is complete or merged, it must pass the entire automated testing framework:
  `swift test`, `xcodebuild test` for unit/component tests, `xcodebuild test` for Visual Regression
  tests when applicable, `xcodebuild test` for UI integration tests, and `swiftlint lint --quiet`.
- If View or Theme files changed, Ralph screenshot verification is also part of the final gate.
- After the UI target exists and is stable, update Ralph's README, implement prompt, and gate script
  so autonomous issues cannot complete without the full framework.

Implementation slices:

1. Mechanical structure migration: move the existing tests, update project configuration, regenerate
   Xcode, and verify the current suite still passes.
2. Component/state-contract expansion: add missing component tests using shared `Tests/Support`
   builders.
3. UI integration target: add `Tests/UI` and cover the agreed fixture-driven user flows.
4. Fixture unification: promote ad hoc fixtures and the launch fixture into named shared scenarios.
5. Ralph gate update: run the full framework before autonomous issues can complete.

Representative UI-test scope:

- Launch with a deterministic fixture and verify the Current Session renders.
- Log the active Set through the real controls and verify the next active Set advances.
- Move On and dismiss the Move On Celebration.
- Open Block Overview, switch Sessions, and return to the Current Session.
- Open Settings, exercise one sign-out route, and exercise one representative pending-write
  confirmation path.
- Open Developer Tools through the real route and verify the route loads.
- Cover one Open Exercise makeup path.
- Cover one Partially Uploaded Block path where Unavailable Sessions stay inert and terminal Move On
  returns to the Block grid.

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
