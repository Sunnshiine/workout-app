import XCTest

final class WorkoutTrackerOnboardingSwitchUITests: XCTestCase {
    /// Covers the onboarding sheet-selection path, which previously wrote the selection straight to
    /// settings without syncing. It must now run the safe switch transaction: auto-sync the newly
    /// selected sheet and land on its freshly parsed session, never presenting the stale cached Block.
    @MainActor
    func testOnboardingSheetSelectionAutoSyncsAndReplacesStaleCachedBlock() throws {
        let app = launchWorkoutApp(fixture: .onboarding)

        XCTAssertTrue(app.staticTexts["Choose your training sheet"].appears(within: 3))
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)

        let replacementRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Replacement Training Log")
        ).firstMatch
        XCTAssertTrue(replacementRow.appears(within: 3))
        replacementRow.tap()

        XCTAssertTrue(app.staticTexts["Replacement Squat"].appears(within: 3))
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)
    }

    /// Pins the identifier and the accessible name on the URL field. Without the label an empty
    /// field has no name for VoiceOver to read, and without the identifier no recipe can target it
    /// except by coordinate. The assertion before `typeText` is the one that fails unlabelled.
    @MainActor
    func testPastedURLGoesThroughANamedFieldAndLandsOnTheSyncedSession() throws {
        let app = launchWorkoutApp(fixture: .onboarding)

        XCTAssertTrue(app.staticTexts["Choose your training sheet"].appears(within: 3))
        tapWhenHittable(app.buttons["Paste a URL instead"])

        let field = app.textFields["onboarding-url-field"]
        XCTAssertTrue(field.appears(within: 3))
        XCTAssertEqual(field.label, "Google Sheet URL")

        tapWhenHittable(field)
        XCTAssertTrue(app.keyboards.firstMatch.appears(within: 3))
        field.typeText("https://docs.google.com/spreadsheets/d/REPLACEMENT/edit")
        XCTAssertEqual(field.label, "Google Sheet URL")

        tapWhenHittable(app.buttons["Save"])

        XCTAssertTrue(app.staticTexts["Replacement Squat"].appears(within: 3))
    }
}
