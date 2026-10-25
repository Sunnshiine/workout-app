import Foundation
import Testing

@testable import WorkoutTracker

private struct RoundTripSheet: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let workbook: LocalWorkbook
    /// How many Sets Week 1's Available Sessions hold, counted from the Sets cells of the rows the
    /// coach left visible.
    let weekOneSetCount: Int
}

/// `fresh-block` with `cells` written over Block 27, where a nil value clears the cell, and with
/// `hiddenRows` hidden by the coach.
private func freshBlock(_ cells: [String: String?] = [:], hiding hiddenRows: [Int] = []) -> LocalWorkbook {
    var workbook = WorkbookScenario.freshBlock.workbook()
    var tab = workbook.tabs["Block 27"]!
    for (cell, value) in cells {
        tab.cells[cell] = value
    }
    for row in hiddenRows {
        tab.hiddenRows[row] = SheetRowVisibility(hiddenByUser: true, hiddenByFilter: false)
    }
    workbook.tabs["Block 27"] = tab
    return workbook
}

@MainActor
private func weekOneSets(of app: WorkoutApplication) throws -> [SetSnapshot] {
    try app.snapshot().sessions
        .filter { $0.id.week == 1 && $0.available }
        .flatMap { try app.session($0.id).exercises.flatMap(\.sets) }
}

/// Every Set the parser surfaces, logged with a Set Log of its own and flushed, reads back that Set
/// Log after the next sync. A write addressed by less than the parser's identity for its Set, such as
/// the first Exercise of a name (#813), lands on another Set's row and fails here.
@MainActor
@Test(arguments: [
    RoundTripSheet(
        testDescription: "two Exercises named Back Squat in one Session",
        workbook: freshBlock([
            "C15": "Back Squat", "D15": "1", "F15": "1", "H15": "RPE8",
            "C19": "Back Squat", "D19": "3", "F19": "5", "H19": "RPE7", "K19": nil
        ]),
        weekOneSetCount: 9
    ),
    RoundTripSheet(
        testDescription: "a Coach Note that moves its Exercise's Set Logs to the Visible Writable Row",
        workbook: freshBlock(),
        weekOneSetCount: 10
    ),
    RoundTripSheet(
        testDescription: "Prescription Lines, the first holding a Coach Note that moves its Set Logs to the spare row",
        workbook: WorkbookScenario.partialUpload.workbook(),
        weekOneSetCount: 9
    ),
    RoundTripSheet(
        testDescription: "a hidden Back Squat above a visible one, and a hidden row under the visible one's Coach Note",
        workbook: freshBlock(["C19": "Back Squat"], hiding: [15, 20]),
        weekOneSetCount: 4
    ),
    RoundTripSheet(
        testDescription: "Set Logs the coach spelled differently, corrected by the athlete",
        workbook: freshBlock(["K15": "185.0x5@8, 185 x 5 @ 8", "K20": "200.0x8@8"]),
        weekOneSetCount: 10
    )
])
private func everySetReadsBackTheSetLogFlushedForIt(_ sheet: RoundTripSheet) async throws {
    let app = try WorkoutApplication(environment: .inMemory(workbook: sheet.workbook))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    let sets = try weekOneSets(of: app)
    let setLogs = sets.indices.map { "\(200 + 5 * $0)x5@8" }

    for (set, setLog) in zip(sets, setLogs) {
        _ = try app.log(set.id, setLog: setLog)
    }
    let flush = try await app.flush()
    _ = try await app.sync()

    #expect(sets.count == sheet.weekOneSetCount)
    #expect(flush.conflictedWrites == [])
    let readBack = try weekOneSets(of: app)
    #expect(readBack.map(\.id) == sets.map(\.id))
    #expect(readBack.map(\.setLog) == setLogs)
}
