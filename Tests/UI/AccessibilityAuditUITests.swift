import XCTest

/// The queue sheet, the History sheet, and the Block grid scroll, and the Visual host cannot read
/// a SwiftUI ScrollView's content, so these run against the app: every control on screen carries a
/// label and a 44pt hit area that overlaps no other, at the default text size and the largest
/// (DESIGN.md §8). XCUI reads the frames the screen draws, so a medium detent's scale counts too.
final class AccessibilityAuditUITests: XCTestCase {
    private static let contentSizes = ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"]

    @MainActor
    func testQueueSheetControlsAreLabeledFingerSizedAndApart() throws {
        for contentSize in Self.contentSizes {
            let app = launch(at: contentSize)
            app.buttons["stage-queue-button"].tap()
            XCTAssertTrue(app.buttons["queue-move-on-button"].appears(within: uiEventBudget))
            let queue = NSPredicate(
                format:
                    "(identifier BEGINSWITH 'stage-queue-' AND identifier != 'stage-queue-button') OR identifier == 'queue-move-on-button'"
            )
            assertAudited(app.buttons.matching(queue), in: app, contentSize)
        }
    }

    @MainActor
    func testHistorySheetControlsAreLabeledFingerSizedAndApart() throws {
        for contentSize in Self.contentSizes {
            let app = launch(at: contentSize)
            tapWhenHittable(app.buttons["last-performed-line"])
            XCTAssertTrue(app.buttons["history-volume-toggle"].appears(within: uiEventBudget))
            let history = NSPredicate(format: "identifier IN {'history-volume-toggle', 'history-row-gutter'}")
            assertAudited(app.buttons.matching(history), in: app, contentSize)
        }
    }

    @MainActor
    func testBlockGridControlsAreLabeledFingerSizedAndApart() throws {
        for contentSize in Self.contentSizes {
            let app = launch(at: contentSize)
            app.buttons["session-location-button"].tap()
            XCTAssertTrue(app.buttons["block-overview-settings-row"].appears(within: uiEventBudget))
            let grid = NSPredicate(format: "identifier BEGINSWITH 'session-tile-' OR identifier == 'block-overview-settings-row'")
            assertAudited(app.buttons.matching(grid), in: app, contentSize)
        }
    }

    @MainActor
    private func launch(at contentSize: String) -> XCUIApplication {
        let app = launchWorkoutApp(fixture: .currentSession, contentSize: contentSize)
        XCTAssertTrue(app.buttons["stage-queue-button"].appears(within: uiEventBudget))
        return app
    }

    /// A control scrolled past the window's edge is out of reach, so only those fully on screen
    /// count. Half a point of slack absorbs the detent's scale rounding a 46pt control to 43.9.
    @MainActor
    private func assertAudited(_ query: XCUIElementQuery, in app: XCUIApplication, _ contentSize: String) {
        let window = app.windows.firstMatch.frame
        let controls = query.allElementsBoundByIndex
            .filter { $0.isEnabled }
            .map { (label: $0.label, frame: $0.frame) }
            .filter { window.contains($0.frame) }
        XCTAssertFalse(controls.isEmpty, "no controls on screen at \(contentSize)")
        for control in controls {
            XCTAssertFalse(control.label.isEmpty, "an unlabeled control at \(control.frame) at \(contentSize)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 43.5, "\(control.label) at \(contentSize)")
            XCTAssertGreaterThanOrEqual(control.frame.height, 43.5, "\(control.label) at \(contentSize)")
        }
        for (index, control) in controls.enumerated() {
            for other in controls[(index + 1)...] {
                let overlap = control.frame.intersection(other.frame)
                XCTAssertTrue(
                    overlap.width < 0.5 || overlap.height < 0.5,
                    "\(control.label) overlaps \(other.label) at \(contentSize)"
                )
            }
        }
    }
}
