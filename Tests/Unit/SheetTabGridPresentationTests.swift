import Foundation
import Testing

@testable import WorkoutTracker

private func grid(_ values: SheetGrid, rowVisibility: [Int: SheetRowVisibility] = [:]) -> SheetTabGridPresentation {
    SheetTabGridPresentation(
        SheetTabSnapshot(tab: "Block 1", snapshot: SheetSnapshot(values: values, rowVisibility: rowVisibility))
    )
}

@Test func theGridEndsAtTheLastRowAndColumnHoldingAValue() {
    let presentation = grid([
        ["", "", "", ""],
        ["Squat", ""],
        ["", "", "365", "", ""],
        ["", "", "", "", "", ""]
    ])

    #expect(presentation.columns == ["A", "B", "C"])
    #expect(presentation.rows.map(\.number) == [1, 2, 3])
    #expect(presentation.rows.map(\.cells) == [["", "", ""], ["Squat", "", ""], ["", "", "365"]])
}

@Test func columnLettersRunPastZ() {
    var row = [String](repeating: "", count: 27)
    row[26] = "Day 3"
    let presentation = grid([row])

    #expect(presentation.columns.count == 27)
    #expect(presentation.columns.suffix(2) == ["Z", "AA"])
    #expect(SheetTabGridPresentation.cellReference(row: 37, column: 26) == "AA37")
}

@Test func aHiddenRowStaysInTheGridFlagged() {
    let presentation = grid(
        [["Day 1"], ["Back Squat"], ["Bench Press"], ["Deadlift"]],
        rowVisibility: [
            1: SheetRowVisibility(hiddenByUser: true),
            2: SheetRowVisibility(),
            3: SheetRowVisibility(hiddenByFilter: true)
        ]
    )

    #expect(presentation.rows.map(\.cells) == [["Day 1"], ["Back Squat"], ["Bench Press"], ["Deadlift"]])
    #expect(presentation.rows.map(\.isHidden) == [false, true, false, true])
}

@Test func anEmptyTabHasNoRowsOrColumns() {
    let presentation = grid([["", ""], [""]])

    #expect(presentation.columns.isEmpty)
    #expect(presentation.rows.isEmpty)
    #expect(presentation.weekHeaderRows.isEmpty)
}

@MainActor
@Test func theLiveReadOfTheBlockTabMapsEachWeekToItsDayHeaderRow() async throws {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)

    let presentation = SheetTabGridPresentation(try await app.sheet(tab: nil))

    #expect(presentation.weekHeaderRows == [1: 12, 2: 37])
    #expect(presentation.rows[36].number == 37)
    #expect(presentation.rows[36].cells[34] == "Day 3")
    #expect(presentation.columns[34] == "AI")
}
