import Testing

@testable import WorkoutTracker

@Test func growingWriteExtendsTheGridDownAndRightLeavingNewCellsEmpty() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["seed"]]])

    try await client.updateCells(spreadsheetId: "sid", range: "'Block 27'!B3:C4", values: [["B3", "C3"], ["B4", "C4"]])

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["seed"], [], ["", "B3", "C3"], ["", "B4", "C4"]])
}

@Test func growingWriteLeavesShorterNeighbouringRowsRagged() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a"], ["b", "c"], []]])

    try await client.updateCells(spreadsheetId: "sid", range: "'Block 27'!C2", values: [["C2"]])

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["a"], ["b", "c", "C2"], []])
}

@Test func writeInsideTheGridOverwritesWithoutChangingItsShape() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a", "b"], ["c", "d"]]])

    try await client.updateCells(spreadsheetId: "sid", range: "'Block 27'!A1:B1", values: [["A", "B"]])

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["A", "B"], ["c", "d"]])
}

@Test func rangeWithFewerRowsThanItSpansIsRejectedWithItsCounts() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a"]]])

    await #expect(throws: LocalWorkbookSheetsClientError.unsupportedValues("Expected 2 row(s), got 1")) {
        try await client.updateCells(spreadsheetId: "sid", range: "'Block 27'!A1:A2", values: [["only one row"]])
    }

    #expect(try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27") == [["a"]])
}

@Test func lowercaseRangeWritesTheSameCellAsItsUppercaseSpelling() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a"]]])

    try await client.updateCells(spreadsheetId: "sid", range: "'Block 27'!b2:c2", values: [["B2", "C2"]])

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["a"], ["", "B2", "C2"]])
}

@Test func rangeWhoseEndPrecedesItsStartIsRejectedAsMalformed() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a"]]])

    for range in ["'Block 27'!B2:A2", "'Block 27'!B2:B1", "'Block 27'!B2:A1"] {
        await #expect(throws: LocalWorkbookSheetsClientError.malformedRange(range), "\(range)") {
            try await client.updateCells(spreadsheetId: "sid", range: range, values: [["changed"]])
        }
    }
}

@Test func rangeWithMoreThanTwoCellReferencesIsRejectedAsMalformed() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a"]]])

    await #expect(throws: LocalWorkbookSheetsClientError.malformedRange("'Block 27'!A1:B2:C3")) {
        try await client.updateCells(spreadsheetId: "sid", range: "'Block 27'!A1:B2:C3", values: [["changed"]])
    }
}
