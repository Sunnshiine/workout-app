import Testing

@testable import WorkoutTracker

@Test func localWorkbookListsAndFetchesSeededTabs() async throws {
    let block27 = gridFromA1(["A1": "Block 27 marker"], rows: 2, cols: 2)
    let block26 = gridFromA1(["B2": "Block 26 marker"], rows: 3, cols: 3)
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": block27,
            "Block 26": block26
        ]
    )

    let titles = try await client.listTabTitles(spreadsheetId: "sid")
    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")

    #expect(titles == ["Block 26", "Block 27"])
    #expect(fetched == block27)
}

@Test func localWorkbookSingleCellWritePersistsForLaterFetchAndGrowsGrid() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1(["A1": "seed"], rows: 1, cols: 1)]
    )

    try await client.write([SheetCellWrite(tabName: "Block 27", row: 2, col: 2, value: "grown")], spreadsheetId: "sid")

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 0, col: 0) == "seed")
    #expect(fetched.cell(row: 2, col: 2) == "grown")
}

@Test func localWorkbookPreservesSeededRowVisibilityAcrossWrites() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": SheetSnapshot(
                values: gridFromA1(["A1": "seed"], rows: 2, cols: 2),
                rowVisibility: [
                    0: SheetRowVisibility(hiddenByUser: true),
                    1: SheetRowVisibility(hiddenByFilter: true)
                ]
            )
        ]
    )

    try await client.write([SheetCellWrite(tabName: "Block 27", row: 1, col: 1, value: "changed")], spreadsheetId: "sid")

    let snapshot = try await client.fetchTabSnapshot(spreadsheetId: "sid", tabName: "Block 27")
    let valuesOnly = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(snapshot.values.cell(row: 1, col: 1) == "changed")
    #expect(snapshot.isRowVisible(0) == false)
    #expect(snapshot.isRowVisible(1) == false)
    #expect(snapshot.isRowVisible(2) == true)
    #expect(valuesOnly.cell(row: 1, col: 1) == "changed")
}

@Test func localWorkbookBlankWritePersistsEmptyString() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1(["K15": "185x5@8"], rows: 20, cols: 12)]
    )

    try await client.write([SheetCellWrite(tabName: "Block 27", row: 14, col: 10, value: "")], spreadsheetId: "sid")

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 14, col: 10) == "")
}

@Test func localWorkbookBatchWriteCommitsEveryUpdateAndRecordsTheBatch() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": gridFromA1(
                [
                    "A1": "old A",
                    "B1": "old B"
                ],
                rows: 1,
                cols: 2
            )
        ]
    )

    let cells = [
        SheetCellWrite(tabName: "Block 27", row: 0, col: 0, value: "new A"),
        SheetCellWrite(tabName: "Block 27", row: 0, col: 1, value: "new B")
    ]
    try await client.write(cells, spreadsheetId: "sid")

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches

    #expect(fetched.cell(row: 0, col: 0) == "new A")
    #expect(fetched.cell(row: 0, col: 1) == "new B")
    #expect(batches == [cells])
}

@Test func localWorkbookEmptyBatchWriteIsNoOpAndUnrecorded() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    try await client.write([], spreadsheetId: "sid")

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == original)
    #expect(await client.recordedBatches.isEmpty)
}

@Test func localWorkbookFailedBatchLeavesWorkbookUnchangedAndUnrecorded() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(throws: LocalWorkbookSheetsClientError.unknownTab("Missing")) {
        try await client.write(
            [
                SheetCellWrite(tabName: "Block 27", row: 0, col: 0, value: "changed"),
                SheetCellWrite(tabName: "Missing", row: 0, col: 0, value: "should throw")
            ],
            spreadsheetId: "sid"
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches
    #expect(fetched == original)
    #expect(batches.isEmpty)
}
