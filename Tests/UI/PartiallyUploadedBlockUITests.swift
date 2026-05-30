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
}
