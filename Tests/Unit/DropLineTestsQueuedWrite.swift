import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)

/// W1 D1 of the fresh block holds `HB SQ` 1x6 on row 15, a blank row 16, a `2 x 10` back-off Line on
/// row 17, and `Next Lift` on row 19. `sheet` stands in for the coach editing the Sheet.
@MainActor
private func makeBackOffApp() async throws -> (app: WorkoutApplication, sheet: LocalWorkbookSheetsClient) {
    var workbook = WorkbookScenario.freshBlock.workbook()
    var tab = try #require(workbook.tabs["Block 27"])
    tab.cells = tab.cells.filter { key, _ in key.wholeMatch(of: /[C-K](1[5-9]|2\d|3[0-6])/) == nil }
    tab.cells.merge(
        [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8",
            "D17": "2", "F17": "10", "H17": "RPE7",
            "C19": "Next Lift", "D19": "2", "F19": "10", "H19": "RPE8"
        ]
    ) { _, new in new }
    workbook.tabs["Block 27"] = tab
    let sheet = LocalWorkbookSheetsClient(workbook: workbook, failedUpdateRequestNumbers: [])
    let app = try WorkoutApplication(environment: .inMemory(sheets: sheet, now: { frozenNow }))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return (app, sheet)
}

/// A queued Set Log names its Set by index. A Drop line the coach writes above a later Line, or one
/// the app reads for the first time after an update, comes after that Line's Sets, so the queued
/// log stays on the Set it was logged on and lands in that Set's cell.
@MainActor
@Test func aQueuedSetLogStaysOnItsSetWhenTheCoachAddsADropAboveIt() async throws {
    let (app, sheet) = try await makeBackOffApp()

    _ = try app.log(try #require(SetAddress("w1d1.e0.s1")), setLog: "100x10@7")
    try await sheet.write(
        [SheetCellWrite(tabName: "Block 27", a1: "F16", value: "8"), SheetCellWrite(tabName: "Block 27", a1: "H16", value: "Drop 20%")],
        spreadsheetId: "FIXTURE"
    )
    _ = try await app.sync()
    let flush = try await app.flush()

    #expect(flush.conflictedWrites == [])
    let cells = try await app.sheet(tab: nil).cells
    #expect(cells["K17"] == "100x10@7")
    #expect(cells["K16"] == nil)
    let sets = try app.session(SessionAddress(week: 1, day: 1)).exercises[0].sets
    #expect(sets.map(\.prescribedLoad) == ["RPE8", "RPE7", "RPE7", "Drop 20%"])
    #expect(sets.map(\.setLog) == [nil, "100x10@7", nil, nil])
}
