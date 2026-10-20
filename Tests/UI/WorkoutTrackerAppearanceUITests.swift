import XCTest

final class WorkoutTrackerAppearanceUITests: XCTestCase {
    @MainActor
    func testSettingsAppearancePickerIsReachableAndWired() throws {
        let app = launchSettingsFixtureApp()

        let picker = app.segmentedControls["settings-appearance-picker"]
        XCTAssertTrue(picker.appears(within: 3))
        XCTAssertTrue(app.buttons["System"].exists)
        XCTAssertTrue(app.buttons["Light"].exists)
        XCTAssertTrue(app.buttons["Night"].exists)
        XCTAssertFalse(app.buttons["Black"].exists)
        XCTAssertFalse(app.buttons["Mint Green"].exists)
        XCTAssertFalse(app.buttons["Blue Light"].exists)

        app.buttons["Light"].tap()
        app.buttons["Night"].tap()
    }

    @MainActor
    private func launchSettingsFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .settings)
    }
}
