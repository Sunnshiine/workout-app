import XCTest

enum WorkoutUITestFixture {
    case currentSession
    case settings
    case longSession
    case partiallyUploadedBlock
    case completedSessionWithOpenExercises

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
        case .completedSessionWithOpenExercises:
            ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_COMPLETED_OPEN_EXERCISES"]
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
