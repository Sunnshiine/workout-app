import XCTest

enum WorkoutUITestFixture {
    case currentSession
    case settings
    case onboarding
    case longSession
    case partiallyUploadedBlock
    case completedSessionWithOpenExercises

    var launchArguments: [String] {
        switch self {
        case .currentSession:
            ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_FULL_BLOCK"]
        case .settings:
            ["-UITEST_FIXTURE", "-UITEST_SETTINGS", "-UITEST_FULL_BLOCK"]
        case .onboarding:
            ["-UITEST_FIXTURE", "-UITEST_ONBOARDING", "-UITEST_FULL_BLOCK"]
        case .longSession:
            ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_LONG_SESSION"]
        case .partiallyUploadedBlock:
            ["-UITEST_FIXTURE"]
        case .completedSessionWithOpenExercises:
            ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_COMPLETED_OPEN_EXERCISES"]
        }
    }
}

enum WorkoutUITestFixtureOption: String {
    case openExercises = "-UITEST_OPEN_EXERCISES"
    case pendingWrite = "-UITEST_PENDING_WRITE"
    case lateSignIn = "-UITEST_LATE_SIGN_IN"
    /// Keeps a log queued, so the `N unsynced` banner stays up instead of flashing `Syncing` and
    /// leaving, for a test that reads the banner or measures the layout under it.
    case offline = "-UITEST_OFFLINE"
}

extension XCTestCase {
    @MainActor
    /// `transcript` is what the Active Set Card's mic hears on every press; nil leaves the mic off.
    func launchWorkoutApp(
        fixture: WorkoutUITestFixture,
        options: [WorkoutUITestFixtureOption] = [],
        animated: Bool = false,
        dictating transcript: String? = nil
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments =
            fixture.launchArguments + options.map(\.rawValue)
            + (animated ? [] : ["-UITEST_DISABLE_ANIMATIONS"]) + ["-UITEST_DISABLE_LIVE_ACTIVITIES"]
            + (transcript.map { ["-UITEST_DICTATION", $0] } ?? [])
        app.launch()
        return app
    }
}

/// How long a UI test waits for something it expects to happen. A wait that succeeds returns as
/// soon as its condition holds, so the budget costs time only on a failure. MEASUREMENT PENDING.
let uiEventBudget: TimeInterval = 10

extension XCUIElement {
    /// `waitForExistence` schedules its first check about a second out, while a bare `exists`
    /// query answers in 20 ms on this app's tree, so poll it instead.
    @MainActor
    func appears(within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let kbtStart = Date()
        repeat {
            if exists {
                print("KBT wait=appears budget=\(timeout) t=\(Date().timeIntervalSince(kbtStart))")
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }
}

@MainActor
func waitForLabel(_ label: String, on element: XCUIElement) {
    XCTAssertTrue(element.appears(within: uiEventBudget), "Expected element for label '\(label)' to exist")
    let deadline = Date().addingTimeInterval(uiEventBudget)
    let kbtStart = Date()
    while Date() < deadline {
        if element.label == label {
            print("KBT wait=label t=\(Date().timeIntervalSince(kbtStart))")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have label '\(label)', got '\(element.label)'")
}

@MainActor
func waitUntilEnabled(_ element: XCUIElement) {
    XCTAssertTrue(element.appears(within: uiEventBudget))
    let deadline = Date().addingTimeInterval(uiEventBudget)
    let kbtStart = Date()
    while Date() < deadline {
        if element.isEnabled {
            print("KBT wait=enabled t=\(Date().timeIntervalSince(kbtStart))")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to become enabled")
}

@MainActor
func tapWhenHittable(_ element: XCUIElement) {
    XCTAssertTrue(element.appears(within: uiEventBudget))
    let deadline = Date().addingTimeInterval(uiEventBudget)
    let kbtStart = Date()
    while Date() < deadline {
        if element.isHittable {
            print("KBT wait=hittable t=\(Date().timeIntervalSince(kbtStart))")
            element.tap()
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to become hittable")
}

@MainActor
func waitForValue(_ value: String, on element: XCUIElement) {
    XCTAssertTrue(element.appears(within: uiEventBudget))
    let deadline = Date().addingTimeInterval(uiEventBudget)
    let kbtStart = Date()
    while Date() < deadline {
        if element.value as? String == value {
            print("KBT wait=value t=\(Date().timeIntervalSince(kbtStart))")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have value '\(value)', got '\(String(describing: element.value))'")
}

@MainActor
func waitForValueContaining(_ value: String, on element: XCUIElement) {
    XCTAssertTrue(element.appears(within: uiEventBudget))
    let deadline = Date().addingTimeInterval(uiEventBudget)
    let kbtStart = Date()
    while Date() < deadline {
        if let elementValue = element.value as? String, elementValue.contains(value) {
            print("KBT wait=valuecontaining t=\(Date().timeIntervalSince(kbtStart))")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have value containing '\(value)', got '\(String(describing: element.value))'")
}
