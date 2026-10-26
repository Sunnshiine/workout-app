import Foundation
import Testing

@testable import WorkoutTracker

private func presentation(
    _ cells: [String: String],
    hiddenRows: [Int: SheetRowVisibility] = [:]
) -> SheetTabGridPresentation {
    let indices = cells.keys.compactMap(a1CellIndex)
    let grid = gridFromA1(
        cells,
        rows: (indices.map(\.row).max() ?? -1) + 1,
        cols: (indices.map(\.col).max() ?? -1) + 1
    )
    let visibility = Dictionary(uniqueKeysWithValues: hiddenRows.map { ($0.key - 1, $0.value) })
    return SheetTabGridPresentation(
        SheetTabSnapshot(tab: "Block 1", snapshot: SheetSnapshot(values: grid, rowVisibility: visibility))
    )
}

private let oneDay: [String: String] = [
    "A1": "Training Max", "B2": "Squat", "C2": "365",
    "B4": "Day 1", "B5": "5/4/2026",
    "C6": "Sets", "E6": "Reps", "F6": "Notes",
    "B7": "Back Squat", "C7": "3", "E7": "5",
    "B9": "BB RDL", "C9": "2", "F9": "Start w/ 10 sec hold"
]

@Test func aDayKeepsOnlyTheRowsAndColumnsOfItsSectionThatHoldAValue() throws {
    let day = try #require(presentation(oneDay).weeks.first?.days.first)

    #expect(day.columns.map(SheetTabGridPresentation.columnLetter) == ["B", "C", "E", "F"])
    #expect(day.rows.map(\.number) == [4, 5, 6, 7, 9])
    #expect(
        day.rows.map(\.cells) == [
            ["Day 1", "", "", ""],
            ["5/4/2026", "", "", ""],
            ["", "Sets", "Reps", "Notes"],
            ["Back Squat", "3", "5", ""],
            ["BB RDL", "2", "", "Start w/ 10 sec hold"]
        ]
    )
}

@Test func aHiddenRowInADayStaysFlagged() throws {
    let day = try #require(
        presentation(oneDay, hiddenRows: [7: SheetRowVisibility(hiddenByUser: true)]).weeks.first?.days.first
    )

    #expect(day.rows.filter(\.isHidden).map(\.number) == [7])
}

@Test func aCellReferenceNamesTheSheetColumnPastZ() {
    #expect(SheetTabGridPresentation.columnLetter(26) == "AA")
    #expect(SheetTabGridPresentation.cellReference(row: 37, column: 34) == "AI37")
}

@Test func aTabWithNoDayHeadersHasNoWeeks() {
    #expect(presentation(["A1": "Training Max", "B2": "Squat"]).weeks.isEmpty)
}

@MainActor
@Test func theLiveReadOfTheBlockTabSplitsIntoEachWeeksDays() async throws {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)

    let weeks = SheetTabGridPresentation(try await app.sheet(tab: nil)).weeks

    #expect(weeks.map(\.number) == [1, 2])
    #expect(weeks.map { $0.days.map(\.number) } == [[1, 2], [1, 2, 3]])
    let weekOneDayOne = try #require(weeks.first?.days.first)
    #expect(weekOneDayOne.columns.map(SheetTabGridPresentation.columnLetter) == ["C", "D", "F", "G", "H", "I", "K"])
    #expect(weekOneDayOne.rows.map(\.number) == [12, 13, 14, 15, 19])
    #expect(weekOneDayOne.rows.last?.cells == ["2-3:1:0 BB RDL", "2", "8", "", "RPE8", "", "Start w/ 10 sec hold"])
}
