import Testing

@testable import WorkoutTracker

@Test func extractsSpreadsheetId() {
    let url = "https://docs.google.com/spreadsheets/d/1AbC_dEF123/edit#gid=0"
    #expect(extractSpreadsheetId(from: url) == "1AbC_dEF123")
}

@Test func returnsNilForNonSheetUrl() {
    #expect(extractSpreadsheetId(from: "https://example.com/foo") == nil)
}
