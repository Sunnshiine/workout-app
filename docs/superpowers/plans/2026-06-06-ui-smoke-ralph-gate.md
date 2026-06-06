# UI Smoke Ralph Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mechanically isolated XCUITest smoke subset that Ralph can run without executing the full UI Interaction Suite.

**Architecture:** Keep the existing `WorkoutTrackerUITests` Xcode target and move the execution boundary to class-level selectors. Smoke classes end in `UISmokeTests`; interaction-heavy tests stay in non-smoke classes. Ralph's gate, prompt, docs, and Python tests select the smoke classes only.

**Tech Stack:** Swift, XCTest/XCUITest, `xcodebuild`, Python `unittest`, Ralph Python orchestrator, Markdown docs.

---

## File Structure

- Modify `Tests/UI/WorkoutUITestSupport.swift`
  - Own shared UI-test fixture launchers plus common wait/tap helpers needed by smoke and interaction classes.
- Create `Tests/UI/WorkoutTrackerUISmokeTests.swift`
  - Own Current Session, Move On, Current Session override, and Settings pending-write smoke flows.
- Create `Tests/UI/PartiallyUploadedBlockUISmokeTests.swift`
  - Own the Partially Uploaded Block inert/unavailable and available-session smoke flow.
- Modify `Tests/UI/WorkoutTrackerUITests.swift`
  - Remove the broad chained journey from Ralph-eligible coverage.
  - Keep keyboard, overscroll, Open Exercise, Developer Tools, appearance, long-session, and hold gesture coverage outside smoke.
- Modify `Tests/UI/PartiallyUploadedBlockUITests.swift`
  - Remove the smoke flow that moves to `PartiallyUploadedBlockUISmokeTests`.
  - Keep terminal Move On coverage outside smoke.
- Modify `ralph/orchestrator/loop.py`
  - Add stable smoke selector constants and use them in the UI gate command.
  - Stop classifying the full-target selector as Ralph's UI gate.
- Modify `ralph/tests/test_loop.py`
  - Prove Ralph's UI gate selects only smoke classes.
  - Prove the full-target selector is not accepted as the UI gate.
- Create `ralph/tests/test_ui_smoke_policy.py`
  - Guard the prompt and README against reintroducing full-target Ralph UI execution.
- Modify `ralph/prompts/ui-verify.md`
  - Tell UI verification to run UI Integration Smoke by class selector only.
- Modify `ralph/README.md`
  - Replace Ralph/raw probe examples with smoke selectors.
  - Document the UI Interaction Suite as manual or non-Ralph coverage.
- Modify `docs/TESTING.md`
  - Add the concrete smoke and interaction command surfaces while preserving the existing policy.

## Assumptions

- The implementation runs in an isolated worktree.
- `Secrets.xcconfig` is present or bootstrapped before any Xcode app-target command.
- Xcode UI commands use `iPhone 17 Pro` unless the implementer passes a specific simulator UDID.
- `Tests/UI/**` edits are authorized by the issue body before an agent implements Tasks 1-3.
- Maestro, Appium, TestFlight, a new Xcode target, and an Xcode test plan are out of scope.

### Task 1: Move Shared XCUITest Helpers

**Files:**
- Modify: `Tests/UI/WorkoutUITestSupport.swift`
- Modify: `Tests/UI/WorkoutTrackerUITests.swift`

- [ ] **Step 1: Replace `Tests/UI/WorkoutUITestSupport.swift` with shared fixture and helper code**

```swift
import XCTest

enum WorkoutUITestFixture {
    case currentSession
    case settings
    case longSession
    case partiallyUploadedBlock

    var launchArguments: [String] {
        switch self {
        case .currentSession:
            ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_FULL_BLOCK"]
        case .settings:
            ["-UITEST_FIXTURE", "-UITEST_SETTINGS", "-UITEST_FULL_BLOCK"]
        case .longSession:
            ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_LONG_SESSION"]
        case .partiallyUploadedBlock:
            ["-UITEST_FIXTURE", "-UITEST_PARTIAL_BLOCK"]
        }
    }
}

enum WorkoutUITestFixtureOption: String {
    case disableCelebrationBloom = "-UITEST_DISABLE_CELEBRATION_BLOOM"
    case openExercises = "-UITEST_OPEN_EXERCISES"
    case pendingWrite = "-UITEST_PENDING_WRITE"
}

extension XCTestCase {
    @MainActor
    func launchWorkoutApp(
        fixture: WorkoutUITestFixture,
        options: [WorkoutUITestFixtureOption] = []
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = fixture.launchArguments + options.map(\.rawValue)
        app.launch()
        return app
    }
}

@MainActor
func waitForLabel(_ label: String, on element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected element for label '\(label)' to exist")
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.label == label {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have label '\(label)', got '\(element.label)'")
}

@MainActor
func waitUntilEnabled(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.isEnabled {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to become enabled")
}

@MainActor
func tapWhenReady(_ element: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    if element.isHittable {
        element.tap()
        return
    }

    app.swipeUp()
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    element.tap()
}

@MainActor
func tapWhenHittable(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.isHittable {
            element.tap()
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to become hittable")
}

@MainActor
func waitForValue(_ value: String, on element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.value as? String == value {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have value '\(value)', got '\(String(describing: element.value))'")
}

@MainActor
func waitForValueContaining(_ value: String, on element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if let elementValue = element.value as? String, elementValue.contains(value) {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have value containing '\(value)', got '\(String(describing: element.value))'")
}

@MainActor
func moveOnCelebration(in app: XCUIApplication) -> XCUIElement {
    let button = app.buttons["move-on-celebration"]
    if button.waitForExistence(timeout: 1) {
        return button
    }

    let scrollView = app.scrollViews["move-on-celebration"]
    if scrollView.waitForExistence(timeout: 1) {
        return scrollView
    }

    let element = app.otherElements["move-on-celebration"]
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    return element
}
```

- [ ] **Step 2: Remove duplicated private helper functions from `Tests/UI/WorkoutTrackerUITests.swift`**

Remove these private file-level functions from `Tests/UI/WorkoutTrackerUITests.swift` because Task 1 Step 1 adds exact shared replacements to `WorkoutUITestSupport.swift`:

- `tapWhenReady(_:in:)`
- `waitForLabel(_:on:)`
- `waitUntilEnabled(_:)`
- `tapWhenHittable(_:)`

Keep these helpers in `Tests/UI/WorkoutTrackerUITests.swift` because only non-smoke interaction tests use them:

- `tapActiveSetCardHeaderBackground(in:)`
- `revealSessionControlsAndSettingsButton(in:)`
- `overPullSessionHeader(in:)`
- `overPullSessionBody(in:)`
- `pullSessionHeader(in:endY:)`
- `assertMoveOnCelebrationIsUsable(_:in:)`
- `assertElementIsMostlyVisible(_:in:minimumVisibleRatio:)`

- [ ] **Step 3: Verify the duplicate private helpers are gone**

Run:

```bash
rg -n "private func (tapWhenReady|waitForLabel|waitUntilEnabled|tapWhenHittable)" Tests/UI
```

Expected: no output.

- [ ] **Step 4: Run one existing UI test to prove the moved helpers compile**

Run:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .ui-smoke-dd \
  -clonedSourcePackagesDirPath .ui-smoke-spm \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUITests/testActiveSetLogButtonSubmitsFromBackgroundWhileWeightFieldIsFocused
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tests/UI/WorkoutUITestSupport.swift Tests/UI/WorkoutTrackerUITests.swift
git commit -m "test: share UI test helpers"
```

### Task 2: Add Current Session Smoke Class

**Files:**
- Create: `Tests/UI/WorkoutTrackerUISmokeTests.swift`
- Modify: `Tests/UI/WorkoutTrackerUITests.swift`

- [ ] **Step 1: Create `Tests/UI/WorkoutTrackerUISmokeTests.swift`**

```swift
import XCTest

final class WorkoutTrackerUISmokeTests: XCTestCase {
    @MainActor
    func testCurrentSessionLogsFirstSetAndAdvancesActiveSet() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5×5@6", on: logButton)
        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMoveOnAdvancesToNextExercise() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)
        logButton.tap()

        waitForLabel("Weight, 252.5", on: app.buttons["weight-pill"])

        tapWhenReady(app.buttons["move-on-button"], in: app)
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1", on: celebration)

        celebration.tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCurrentSessionOverrideControlsReturnToCurrentSession() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))

        app.buttons["Week 1, Day 3"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])
        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)

        app.buttons["go-back-current-session-button"].tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))
        waitForLabel("Open Block Overview for Week 1, Day 1", on: app.buttons["session-location-button"])
    }

    @MainActor
    func testSettingsPendingWriteSignOutConfirmation() throws {
        let app = launchSettingsSmokeApp()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)

        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Sign Out"].tap()

        XCTAssertTrue(app.staticTexts["Connect your training sheet"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchCurrentSessionSmokeApp() -> XCUIApplication {
        launchWorkoutApp(
            fixture: .currentSession,
            options: [.disableCelebrationBloom]
        )
    }

    @MainActor
    private func launchSettingsSmokeApp() -> XCUIApplication {
        launchWorkoutApp(
            fixture: .settings,
            options: [.pendingWrite]
        )
    }
}
```

- [ ] **Step 2: Replace the first class in `Tests/UI/WorkoutTrackerUITests.swift` with non-smoke interaction coverage**

Replace the existing `final class WorkoutTrackerUITests: XCTestCase` declaration and its full class body with this class:

```swift
final class WorkoutTrackerInteractionUITests: XCTestCase {
    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        tapActiveSetCardHeaderBackground(in: app)

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testActiveSetLogButtonSubmitsFromBackgroundWhileWeightFieldIsFocused() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5×5@6", on: logButton)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        logButton.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDeveloperToolsRouteLoadsFromSettings() throws {
        let app = launchSettingsFixtureApp(options: [.pendingWrite])

        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        let syncNowButton = app.buttons["settings-sync-now-button"]
        let developerToolsRow = app.buttons["settings-developer-tools-row"]
        let signOutButton = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(trainingSheetRow.exists)
        XCTAssertTrue(syncNowButton.exists)
        XCTAssertTrue(developerToolsRow.exists)
        XCTAssertTrue(signOutButton.exists)

        developerToolsRow.tap()
        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Current Session Debug Info"].exists)
        XCTAssertTrue(app.staticTexts["Pending Sheet Writes"].exists)
        XCTAssertTrue(app.staticTexts["Actions"].exists)
        XCTAssertTrue(app.buttons["developer-tools-force-celebration-button"].exists)
        XCTAssertTrue(app.buttons["developer-tools-sync-button"].exists)

        app.navigationBars["Developer Tools"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpenExerciseMakeupFlowShowsLastPerformedAndLogsSet() throws {
        let app = launchFixtureApp(options: [.openExercises])

        app.swipeUp()
        let openBackSquat = app.buttons.containing(.staticText, identifier: "Back Squat").firstMatch
        tapWhenHittable(openBackSquat)

        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)
        XCTAssertTrue(app.staticTexts["Back Squat"].exists)
        XCTAssertTrue(app.staticTexts["Last Performed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["255x5@7"].exists)
        XCTAssertTrue(app.staticTexts["Block 26 · W4 D3"].exists)

        app.buttons["rpe-7"].tap()
        waitForLabel("Log 252.5×5@7", on: app.buttons["log-active-set-button"])
        app.buttons["log-active-set-button"].tap()

        XCTAssertFalse(app.buttons["log-active-set-button"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsRevealGestureOpensSettings() throws {
        let app = launchFixtureApp(options: [.pendingWrite])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-controls-settings-button"].exists)

        let settingsButton = revealSessionControlsAndSettingsButton(in: app)
        XCTAssertTrue(app.otherElements["session-controls"].exists)
        XCTAssertTrue(settingsButton.exists)
        XCTAssertTrue(settingsButton.isHittable)
        XCTAssertFalse(app.buttons["session-controls-sync-button"].exists)

        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)
    }

    @MainActor
    private func launchFixtureApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(
            fixture: .currentSession,
            options: [.disableCelebrationBloom] + options
        )
    }

    @MainActor
    private func launchSettingsFixtureApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(
            fixture: .settings,
            options: [.disableCelebrationBloom] + options
        )
    }
}
```

Leave `WorkoutTrackerAppearanceUITests`, `WorkoutTrackerLongSessionUITests`, and `WorkoutTrackerSkipUITests` in the same file under the replacement class.

- [ ] **Step 3: Verify the broad chained test is gone**

Run:

```bash
rg -n "testFixtureDrivenCoreSessionFlow|testNonCurrentSessionChromeShowsOverrideControlsWithoutSessionControls|testSettingsRevealRouteSmokeOpensSettingsAndPendingSignOutConfirmation" Tests/UI
```

Expected: no output.

- [ ] **Step 4: Run the new Current Session smoke selector**

Run:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .ui-smoke-dd \
  -clonedSourcePackagesDirPath .ui-smoke-spm \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the changed interaction test selector**

Run:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .ui-interaction-dd \
  -clonedSourcePackagesDirPath .ui-interaction-spm \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerInteractionUITests/testSettingsRevealGestureOpensSettings
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Tests/UI/WorkoutTrackerUISmokeTests.swift Tests/UI/WorkoutTrackerUITests.swift
git commit -m "test: isolate current session UI smoke"
```

### Task 3: Add Partially Uploaded Block Smoke Class

**Files:**
- Create: `Tests/UI/PartiallyUploadedBlockUISmokeTests.swift`
- Modify: `Tests/UI/PartiallyUploadedBlockUITests.swift`

- [ ] **Step 1: Create `Tests/UI/PartiallyUploadedBlockUISmokeTests.swift`**

```swift
import XCTest

final class PartiallyUploadedBlockUISmokeTests: XCTestCase {
    @MainActor
    func testUnavailableSessionIsInertAndAvailableSessionOpens() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 5))
        let unavailableTile = app.descendants(matching: .any)["session-tile-W1-D3"]
        XCTAssertTrue(unavailableTile.waitForExistence(timeout: 3))
        waitForValue("Not uploaded", on: unavailableTile)
        XCTAssertFalse(app.buttons["Week 1, Day 3"].exists)

        unavailableTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.navigationBars["Block 27"].exists)
        XCTAssertFalse(app.staticTexts["Bench Press"].exists)

        app.buttons["Week 1, Day 2"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchPartialBlockOverviewApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .partiallyUploadedBlock)
    }
}
```

- [ ] **Step 2: Remove the moved smoke method from `Tests/UI/PartiallyUploadedBlockUITests.swift`**

After removal, `Tests/UI/PartiallyUploadedBlockUITests.swift` should keep this class:

```swift
import XCTest

final class PartiallyUploadedBlockUITests: XCTestCase {
    @MainActor
    func testTerminalMoveOnReturnsToAccessibleBlockGrid() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 5))
        tapElement(withIdentifier: "session-tile-W4-D1", in: app)
        XCTAssertTrue(app.staticTexts["Accessory W4 D1"].waitForExistence(timeout: 3))

        app.buttons["make-current-session-button"].tap()
        XCTAssertTrue(app.buttons["move-on-button"].waitForExistence(timeout: 3))
        app.buttons["move-on-button"].tap()

        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        XCTAssertEqual(celebration.label, "Week 4, Day 1")
        waitForValueContaining("1 Sets, 1 Exercises, 1 Left", on: celebration)

        celebration.tap()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))
        XCTAssertFalse(celebration.exists)
        XCTAssertTrue(app.descendants(matching: .any)["session-tile-W4-D1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["session-tile-W4-D2"].exists)
    }

    @MainActor
    private func launchPartialBlockOverviewApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .partiallyUploadedBlock)
    }

    @MainActor
    private func tapElement(withIdentifier identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        element.tap()
    }
}
```

- [ ] **Step 3: Run the Partially Uploaded Block smoke selector**

Run:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .ui-smoke-dd \
  -clonedSourcePackagesDirPath .ui-smoke-spm \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Tests/UI/PartiallyUploadedBlockUISmokeTests.swift Tests/UI/PartiallyUploadedBlockUITests.swift
git commit -m "test: isolate partial block UI smoke"
```

### Task 4: Repoint Ralph Gate With Python Tests

**Files:**
- Modify: `ralph/tests/test_loop.py`
- Modify: `ralph/orchestrator/loop.py`

- [ ] **Step 1: Write failing Ralph gate tests**

In `ralph/tests/test_loop.py`, add `UI_INTEGRATION_SMOKE_SELECTORS` to the existing `from ralph.orchestrator.loop import` import list:

```python
from ralph.orchestrator.loop import (
    IssueSelector,
    OriginMain,
    RalphLoop,
    RalphLoopError,
    UI_INTEGRATION_SMOKE_SELECTORS,
    _format_ralph_log_line,
    _gate_name_for_command,
    _gate_specs,
)
```

Add these tests inside `class RalphGateSpecTests(unittest.TestCase):`

```python
    def test_ui_gate_runs_only_smoke_class_selectors(self) -> None:
        specs = _gate_specs("iPhone 17 Pro")

        ui = next(spec for spec in specs if spec.name == GATE_UI_INTEGRATION)

        self.assertEqual(
            UI_INTEGRATION_SMOKE_SELECTORS,
            (
                "-only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests",
                "-only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests",
            ),
        )
        self.assertNotIn("-only-testing:WorkoutTrackerUITests", ui.command)
        for selector in UI_INTEGRATION_SMOKE_SELECTORS:
            self.assertIn(selector, ui.command)
        self.assertEqual(_gate_name_for_command(ui.command), GATE_UI_INTEGRATION)

    def test_full_ui_target_selector_is_not_a_ui_gate(self) -> None:
        command = ("xcodebuild", "test", "-only-testing:WorkoutTrackerUITests")

        self.assertEqual(_gate_name_for_command(command), "xcodebuild")
```

- [ ] **Step 2: Run the Ralph gate tests and verify they fail**

Run:

```bash
uv run python -m unittest ralph.tests.test_loop.RalphGateSpecTests -v
```

Expected: FAIL because `UI_INTEGRATION_SMOKE_SELECTORS` is not defined or the full-target selector still maps to `ui-integration-tests`.

- [ ] **Step 3: Add smoke selector constants and command classification in `ralph/orchestrator/loop.py`**

Add this constant near the other gate-related constants in `ralph/orchestrator/loop.py`:

```python
UI_INTEGRATION_SMOKE_SELECTORS = (
    "-only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests",
    "-only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests",
)
```

Replace the UI gate selector at the end of the `GATE_UI_INTEGRATION` command tuple in `_gate_specs`:

```python
                "test",
                *UI_INTEGRATION_SMOKE_SELECTORS,
```

Add this helper above `_gate_name_for_command`:

```python
def _is_ui_smoke_selector(arg: str) -> bool:
    return (
        arg.startswith("-only-testing:WorkoutTrackerUITests/")
        and arg.endswith("UISmokeTests")
    )
```

Replace the UI branch in `_gate_name_for_command`:

```python
    if any(_is_ui_smoke_selector(part) for part in command):
        return GATE_UI_INTEGRATION
```

- [ ] **Step 4: Run the Ralph gate tests and verify they pass**

Run:

```bash
uv run python -m unittest ralph.tests.test_loop.RalphGateSpecTests -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ralph/orchestrator/loop.py ralph/tests/test_loop.py
git commit -m "test: run Ralph UI smoke selectors"
```

### Task 5: Guard Ralph Prompts And Docs

**Files:**
- Create: `ralph/tests/test_ui_smoke_policy.py`
- Modify: `ralph/prompts/ui-verify.md`
- Modify: `ralph/README.md`
- Modify: `docs/TESTING.md`

- [ ] **Step 1: Create failing prompt/docs policy tests**

Create `ralph/tests/test_ui_smoke_policy.py`:

```python
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FULL_TARGET_SELECTOR = re.compile(r"-only-testing:WorkoutTrackerUITests(?:\s|$)")


class RalphUISmokePolicyTests(unittest.TestCase):
    def test_ui_verify_prompt_uses_smoke_selectors(self) -> None:
        prompt = (ROOT / "ralph" / "prompts" / "ui-verify.md").read_text(encoding="utf-8")

        self.assertIn("UI Integration Smoke", prompt)
        self.assertIn("WorkoutTrackerUITests/WorkoutTrackerUISmokeTests", prompt)
        self.assertIn("WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests", prompt)
        self.assertNotIn("Run Xcode UI integration tests for `WorkoutTrackerUITests`.", prompt)
        self.assertIsNone(FULL_TARGET_SELECTOR.search(prompt))

    def test_readme_documents_smoke_and_manual_interaction_suite(self) -> None:
        readme = (ROOT / "ralph" / "README.md").read_text(encoding="utf-8")

        self.assertIn("UI Integration Smoke", readme)
        self.assertIn("WorkoutTrackerUITests/WorkoutTrackerUISmokeTests", readme)
        self.assertIn("WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests", readme)
        self.assertIn("UI Interaction Suite", readme)
        self.assertIn("manual or non-Ralph", readme)
        self.assertNotIn("- Xcode UI integration tests for `WorkoutTrackerUITests`", readme)
        self.assertIsNone(FULL_TARGET_SELECTOR.search(readme))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the policy tests and verify they fail**

Run:

```bash
uv run python -m unittest ralph.tests.test_ui_smoke_policy -v
```

Expected: FAIL because the prompt and README still describe the full UI target.

- [ ] **Step 3: Update `ralph/prompts/ui-verify.md` Work and Completion Gate wording**

Replace the first Work bullet with these bullets:

```markdown
- Run UI Integration Smoke only. Use class-level selectors inside the existing
  `WorkoutTrackerUITests` target:

  ```bash
  xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath .ralph-dd \
    -clonedSourcePackagesDirPath .ralph-spm \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled NO \
    -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
    -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
  ```

- Do not run `-only-testing:WorkoutTrackerUITests`; that selects the full UI
  target. Do not run the UI Interaction Suite during Ralph's autonomous loop.
```

Replace the first completion condition with:

```markdown
- UI Integration Smoke passed through the class-level smoke selectors.
```

- [ ] **Step 4: Update `ralph/README.md` raw UI probe and gate wording**

Replace the raw UI-test probe command under the simulator isolation section with:

```markdown
For raw UI Integration Smoke probes outside Ralph, use the same isolation rule and
keep the selector class-level:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath ".dd-<UDID>" \
  -clonedSourcePackagesDirPath ".spm-<UDID>" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

The UI Interaction Suite remains manual or non-Ralph coverage. Run it only when
higher-flake interaction confidence is explicitly required:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath ".dd-<UDID>-interaction" \
  -clonedSourcePackagesDirPath ".spm-<UDID>-interaction" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerInteractionUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerAppearanceUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerLongSessionUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerSkipUITests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUITests
```
```

Replace the app-gate bullet:

```markdown
- Xcode UI Integration Smoke for class-level smoke selectors in `WorkoutTrackerUITests`
```

- [ ] **Step 5: Update `docs/TESTING.md` command surface**

Under the existing UI XCUITest boundary bullets, add:

```markdown
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
```

- [ ] **Step 6: Run prompt/docs policy tests and Ralph gate tests**

Run:

```bash
uv run python -m unittest \
  ralph.tests.test_loop.RalphGateSpecTests \
  ralph.tests.test_ui_smoke_policy \
  -v
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ralph/tests/test_ui_smoke_policy.py ralph/prompts/ui-verify.md ralph/README.md docs/TESTING.md
git commit -m "docs: document Ralph UI smoke boundary"
```

### Task 6: Final Audit And Verification

**Files:**
- Verify: `Tests/UI/WorkoutTrackerUISmokeTests.swift`
- Verify: `Tests/UI/PartiallyUploadedBlockUISmokeTests.swift`
- Verify: `ralph/orchestrator/loop.py`
- Verify: `ralph/prompts/ui-verify.md`
- Verify: `ralph/README.md`
- Verify: `docs/TESTING.md`

- [ ] **Step 1: Audit full-target selector references**

Run:

```bash
rg -n --fixed-strings -- "-only-testing:WorkoutTrackerUITests" ralph docs/TESTING.md docs/specs/2026-06-06-ui-integration-smoke-ralph-gate.md
```

Expected:
- `ralph/**` references are class-level smoke selectors only.
- `docs/TESTING.md` references are class-level selectors or policy warnings.
- `docs/specs/2026-06-06-ui-integration-smoke-ralph-gate.md` may still mention the removed full-target shape as historical context and as a prohibited command.

- [ ] **Step 2: Run Ralph Python tests for the selector contract**

Run:

```bash
uv run python -m unittest \
  ralph.tests.test_loop.RalphGateSpecTests \
  ralph.tests.test_ui_smoke_policy \
  -v
```

Expected: PASS.

- [ ] **Step 3: Run the combined UI Integration Smoke selector**

Run:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .ui-smoke-dd \
  -clonedSourcePackagesDirPath .ui-smoke-spm \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Run the fast non-UI test gate**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Run SwiftLint when available**

Run:

```bash
if command -v swiftlint >/dev/null 2>&1; then swiftlint lint --quiet; else echo "[info] swiftlint not installed - skipping lint"; fi
```

Expected: PASS, or `[info] swiftlint not installed - skipping lint`.

## Self-Review

- Spec coverage: Tasks 1-3 implement smoke class selectors inside the existing UI target, split the broad journey into short flows, and keep interaction-heavy tests outside smoke. Task 4 repoints Ralph to smoke selectors and rejects the full-target selector. Task 5 updates prompt/docs command surfaces and keeps the UI Interaction Suite manual or non-Ralph. Task 6 verifies the whole contract.
- Placeholder scan: Complete.
- Type consistency: Smoke class names, selector strings, Python constant names, and docs examples all use `WorkoutTrackerUISmokeTests` and `PartiallyUploadedBlockUISmokeTests`.
