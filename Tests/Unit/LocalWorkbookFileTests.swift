import Foundation
import Testing

@testable import WorkoutTracker

private func temporaryWorkbookURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("local-workbook-\(UUID().uuidString)")
        .appendingPathExtension("json")
}

@Test func localWorkbookTabRoundTripsThroughSheetSnapshotIncludingRowVisibility() {
    let snapshot = SheetSnapshot(
        values: gridFromA1(["C12": "Day 1", "K15": "185x5@8"], rows: 20, cols: 12),
        rowVisibility: [
            14: SheetRowVisibility(hiddenByUser: true),
            16: SheetRowVisibility(hiddenByFilter: true)
        ]
    )

    let tab = LocalWorkbook.Tab(snapshot: snapshot)

    #expect(tab.rows == 20)
    #expect(tab.cols == 12)
    #expect(tab.cells == ["C12": "Day 1", "K15": "185x5@8"])
    #expect(tab.hiddenRows == [15: SheetRowVisibility(hiddenByUser: true), 17: SheetRowVisibility(hiddenByFilter: true)])
    #expect(tab.snapshot == snapshot)
}

@Test func localWorkbookEncodesHiddenRowsAsAnObjectKeyedByRowNumberAndDecodesBack() throws {
    let workbook = LocalWorkbook(
        spreadsheetId: "FIXTURE",
        title: "Fixture Training Log",
        tabs: [
            "Block 27": LocalWorkbook.Tab(
                rows: 20,
                cols: 12,
                cells: ["K15": "185x5@8"],
                hiddenRows: [16: SheetRowVisibility(hiddenByUser: true, hiddenByFilter: false)]
            )
        ]
    )

    let data = try JSONEncoder().encode(workbook)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tabs = try #require(json["tabs"] as? [String: Any])
    let block = try #require(tabs["Block 27"] as? [String: Any])
    let hiddenRows = try #require(block["hiddenRows"] as? [String: Any])

    #expect(hiddenRows.keys.sorted() == ["16"])
    #expect(try JSONDecoder().decode(LocalWorkbook.self, from: data) == workbook)
}

@Test func handAuthoredWorkbookWithoutDimensionsGrowsToFitItsCells() throws {
    let json = """
        {
          "spreadsheetId": "FIXTURE",
          "title": "By hand",
          "tabs": { "Block 27": { "cells": { "C12": "Day 1", "K15": "185x5@8" } } }
        }
        """

    let workbook = try JSONDecoder().decode(LocalWorkbook.self, from: Data(json.utf8))
    let snapshot = try #require(workbook.tabs["Block 27"]?.snapshot)

    #expect(snapshot.values.count == 15)
    #expect(snapshot.values.cell(row: 14, col: 10) == "185x5@8")
    #expect(snapshot.values.cell(row: 11, col: 2) == "Day 1")
}

@Test func localWorkbookRejectsMalformedCellKeysAndUppercasesTheRest() throws {
    for bad in ["\"15\"", "\"\"", "\"K0\"", "\"K15 \"", "\"K-1\""] {
        let json = """
            { "spreadsheetId": "s", "title": "t", "tabs": { "B": { "cells": { \(bad): "x" } } } }
            """
        #expect(throws: DecodingError.self, "\(bad)") {
            try JSONDecoder().decode(LocalWorkbook.self, from: Data(json.utf8))
        }
    }

    let lower = """
        { "spreadsheetId": "s", "title": "t", "tabs": { "B": { "cells": { "k15": "185x5@8" } } } }
        """
    let workbook = try JSONDecoder().decode(LocalWorkbook.self, from: Data(lower.utf8))
    #expect(workbook.tabs["B"]?.cells == ["K15": "185x5@8"])
}

@Test func localWorkbookRejectsNonNumericHiddenRowKeys() {
    let json = """
        { "spreadsheetId": "s", "title": "t", "tabs": { "B": { "cells": {}, "hiddenRows": { "row15": {} } } } }
        """

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(LocalWorkbook.self, from: Data(json.utf8))
    }
}

@Test func persistingClientWritesEveryUpdateAndAFreshClientLoadsTheWrittenCell() async throws {
    let url = temporaryWorkbookURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let seed = LocalWorkbook(
        spreadsheetId: "FIXTURE",
        title: "Fixture Training Log",
        tabs: ["Block 27": LocalWorkbook.Tab(rows: 20, cols: 12, cells: ["C15": "Back Squat"])]
    )
    try seed.write(to: url)
    let client = LocalWorkbookSheetsClient(workbook: try LocalWorkbook.load(from: url), persistTo: url)

    try await client.updateCells(spreadsheetId: "FIXTURE", range: "'Block 27'!K15", values: [["185x5@8"]])

    let written = try LocalWorkbook.load(from: url)
    #expect(written.tabs["Block 27"]?.cells == ["C15": "Back Squat", "K15": "185x5@8"])
    #expect(written.spreadsheetId == "FIXTURE")
    #expect(written.title == "Fixture Training Log")

    let reopened = LocalWorkbookSheetsClient(workbook: written)
    let fetched = try await reopened.fetchTab(spreadsheetId: "FIXTURE", tabName: "Block 27")
    #expect(fetched.cell(row: 14, col: 10) == "185x5@8")
}

@Test func persistingClientKeepsMemoryAndDiskInStepWhenTheWriteFails() async throws {
    let url = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)/workbook.json")
    let client = LocalWorkbookSheetsClient(
        workbook: LocalWorkbook(spreadsheetId: "s", title: "t", tabs: ["B": LocalWorkbook.Tab(cells: ["A1": "seed"])]),
        persistTo: url
    )

    await #expect(throws: (any Error).self) {
        try await client.updateCells(spreadsheetId: "s", range: "'B'!A1", values: [["changed"]])
    }

    let fetched = try await client.fetchTab(spreadsheetId: "s", tabName: "B")
    #expect(fetched.cell(row: 0, col: 0) == "seed")
    #expect(await client.recordedBatches.isEmpty)
}
