import Testing

@testable import WorkoutTracker

@Test func growingWriteExtendsTheGridDownAndRightLeavingNewCellsEmpty() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["seed"]]])

    try await client.write([SheetCellWrite(tabName: "Block 27", row: 2, col: 2, value: "C3")], spreadsheetId: "sid")

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["seed"], [], ["", "", "C3"]])
}

@Test func growingWriteLeavesShorterNeighbouringRowsRagged() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a"], ["b", "c"], []]])

    try await client.write([SheetCellWrite(tabName: "Block 27", row: 1, col: 2, value: "C2")], spreadsheetId: "sid")

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["a"], ["b", "c", "C2"], []])
}

@Test func writeInsideTheGridOverwritesWithoutChangingItsShape() async throws {
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": [["a", "b"], ["c", "d"]]])

    try await client.write(
        [
            SheetCellWrite(tabName: "Block 27", row: 0, col: 0, value: "A"),
            SheetCellWrite(tabName: "Block 27", row: 0, col: 1, value: "B")
        ],
        spreadsheetId: "sid"
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == [["A", "B"], ["c", "d"]])
}
