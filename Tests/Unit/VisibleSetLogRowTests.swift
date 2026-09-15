import Testing

@testable import WorkoutTracker

// The Exercise spans rows 10..<15. Rows 11 and 13 are hidden, so the visible rows below the anchor
// are 12 and 14.
private let anchor = SheetLayoutExerciseAnchor(name: "Squat", row: 10, nextAnchorRow: 15)

private func snapshot(hiddenRows: Set<Int> = []) -> SheetSnapshot {
    SheetSnapshot(
        values: Array(repeating: Array(repeating: "", count: 4), count: 20),
        rowVisibility: Dictionary(
            uniqueKeysWithValues: hiddenRows.map { ($0, SheetRowVisibility(hiddenByUser: true)) }
        )
    )
}

@Test func visibleSetLogRowCountsOnlyVisibleRowsBelowTheAnchor() {
    let sheet = snapshot(hiddenRows: [11, 13])

    #expect(anchor.visibleSetLogRow(for: 0, compactHeaderSetOne: false, in: sheet) == 12)
    #expect(anchor.visibleSetLogRow(for: 1, compactHeaderSetOne: false, in: sheet) == 14)
    #expect(anchor.visibleSetLogRow(for: 2, compactHeaderSetOne: false, in: sheet) == nil)
}

@Test func visibleSetLogRowStartsOnTheAnchorRowForACompactHeader() {
    let sheet = snapshot(hiddenRows: [11, 13])

    #expect(anchor.visibleSetLogRow(for: 0, compactHeaderSetOne: true, in: sheet) == 10)
    #expect(anchor.visibleSetLogRow(for: 1, compactHeaderSetOne: true, in: sheet) == 12)
    #expect(anchor.visibleSetLogRow(for: 2, compactHeaderSetOne: true, in: sheet) == 14)
    #expect(anchor.visibleSetLogRow(for: 3, compactHeaderSetOne: true, in: sheet) == nil)
}

@Test func visibleSetLogRowWalksEveryRowOfTheSpanWhenNothingIsHidden() {
    let sheet = snapshot()

    #expect(anchor.visibleSetLogRow(for: 0, compactHeaderSetOne: false, in: sheet) == 11)
    #expect(anchor.visibleSetLogRow(for: 3, compactHeaderSetOne: false, in: sheet) == 14)
    #expect(anchor.visibleSetLogRow(for: 4, compactHeaderSetOne: false, in: sheet) == nil)
}

@Test func visibleSetLogRowRejectsANegativeSetIndex() {
    #expect(anchor.visibleSetLogRow(for: -1, compactHeaderSetOne: false, in: snapshot()) == nil)
    #expect(anchor.visibleSetLogRow(for: -1, compactHeaderSetOne: true, in: snapshot()) == nil)
}

@Test func visibleSetLogRowFindsNoRowWhenEveryRowOfTheSpanIsHidden() {
    let sheet = snapshot(hiddenRows: [10, 11, 12, 13, 14])

    #expect(anchor.visibleSetLogRow(for: 0, compactHeaderSetOne: false, in: sheet) == nil)
    #expect(anchor.visibleSetLogRow(for: 0, compactHeaderSetOne: true, in: sheet) == nil)
}

@Test func visibleSetLogRowFindsNoRowWhenTheExerciseHasNoRowBelowItsAnchor() {
    let lastRow = SheetLayoutExerciseAnchor(name: "Bench", row: 10, nextAnchorRow: 11)

    #expect(lastRow.visibleSetLogRow(for: 0, compactHeaderSetOne: false, in: snapshot()) == nil)
    #expect(lastRow.visibleSetLogRow(for: 0, compactHeaderSetOne: true, in: snapshot()) == 10)
}
