import XCTest

final class PartiallyUploadedBlockUITests: XCTestCase {
    @MainActor
    func testPartiallyUploadedBlockGridShowsUnavailableTilesAsInert() throws {
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
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE", "-UITEST_PARTIAL_BLOCK"]
        app.launch()
        return app
    }

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) {
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
    private func waitForValueContaining(_ value: String, on element: XCUIElement) {
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
    private func tapElement(withIdentifier identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        element.tap()
    }

    @MainActor
    private func moveOnCelebration(in app: XCUIApplication) -> XCUIElement {
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
}
