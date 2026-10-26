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

private func expectCorruptedWorkbook(_ json: String, saying message: String, forKey label: String) throws {
    do {
        _ = try JSONDecoder().decode(LocalWorkbook.self, from: Data(json.utf8))
        Issue.record("\"\(label)\" decoded instead of failing")
    } catch let DecodingError.dataCorrupted(context) {
        #expect(context.debugDescription == message, "\(label)")
    }
}

@Test func localWorkbookRejectsMalformedCellKeysAndUppercasesTheRest() throws {
    for bad in ["15", "", "K0", "K15 ", "K-1"] {
        try expectCorruptedWorkbook(
            """
            { "spreadsheetId": "s", "title": "t", "tabs": { "B": { "cells": { "\(bad)": "x" } } } }
            """,
            saying: "cells keys are A1 references such as K15; got \"\(bad)\"",
            forKey: bad
        )
    }

    let lower = """
        { "spreadsheetId": "s", "title": "t", "tabs": { "B": { "cells": { "k15": "185x5@8" } } } }
        """
    let workbook = try JSONDecoder().decode(LocalWorkbook.self, from: Data(lower.utf8))
    #expect(workbook.tabs["B"]?.cells == ["K15": "185x5@8"])
}

@Test func localWorkbookRejectsHiddenRowKeysThatDoNotNameASheetRow() throws {
    for bad in ["row15", "", "0", "-1", "15.0"] {
        try expectCorruptedWorkbook(
            """
            {
              "spreadsheetId": "s", "title": "t",
              "tabs": {
                "B": { "cells": {}, "hiddenRows": { "\(bad)": { "hiddenByUser": true, "hiddenByFilter": false } } }
              }
            }
            """,
            saying: "hiddenRows keys are 1-based row numbers; got \"\(bad)\"",
            forKey: bad
        )
    }

    let valid = """
        {
          "spreadsheetId": "s", "title": "t",
          "tabs": { "B": { "cells": {}, "hiddenRows": { "15": { "hiddenByUser": false, "hiddenByFilter": true } } } }
        }
        """
    let workbook = try JSONDecoder().decode(LocalWorkbook.self, from: Data(valid.utf8))
    #expect(workbook.tabs["B"]?.hiddenRows == [15: SheetRowVisibility(hiddenByFilter: true)])
}

@Test func twoWorkbookKeysNamingOneLocationCollapseToASingleEntry() throws {
    let json = """
        {
          "spreadsheetId": "s", "title": "t",
          "tabs": {
            "B": {
              "cells": { "k15": "a", "K15": "b" },
              "hiddenRows": {
                "15": { "hiddenByUser": true, "hiddenByFilter": false },
                "015": { "hiddenByUser": true, "hiddenByFilter": false }
              }
            }
          }
        }
        """

    let tab = try #require(try JSONDecoder().decode(LocalWorkbook.self, from: Data(json.utf8)).tabs["B"])

    #expect(tab.cells.keys.sorted() == ["K15"])
    #expect(tab.hiddenRows == [15: SheetRowVisibility(hiddenByUser: true)])
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
    let client = try LocalWorkbookSheetsClient(file: url)

    try await client.write([SheetCellWrite(tabName: "Block 27", row: 14, col: 10, value: "185x5@8")], spreadsheetId: "FIXTURE")

    let written = try LocalWorkbook.load(from: url)
    #expect(written.tabs["Block 27"]?.cells == ["C15": "Back Squat", "K15": "185x5@8"])
    #expect(written.spreadsheetId == "FIXTURE")
    #expect(written.title == "Fixture Training Log")

    let reopened = LocalWorkbookSheetsClient(workbook: written)
    let fetched = try await reopened.fetchTab(spreadsheetId: "FIXTURE", tabName: "Block 27")
    #expect(fetched.cell(row: 14, col: 10) == "185x5@8")
}

@Test func aFailedWriteLeavesTheFileAndTheRecordedBatchesAsTheyWere() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-workbook-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("workbook.json")
    try LocalWorkbook(spreadsheetId: "s", title: "t", tabs: ["B": LocalWorkbook.Tab(cells: ["A1": "seed"])]).write(to: url)
    let client = try LocalWorkbookSheetsClient(file: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    await #expect(throws: (any Error).self) {
        try await client.write([SheetCellWrite(tabName: "B", row: 0, col: 0, value: "changed")], spreadsheetId: "s")
    }

    let fetched = try await client.fetchTab(spreadsheetId: "s", tabName: "B")
    #expect(fetched.cell(row: 0, col: 0) == "seed")
    #expect(try LocalWorkbook.load(from: url).tabs["B"]?.cells == ["A1": "seed"])
    #expect(await client.recordedBatches.isEmpty)
}

@Test func anEditToTheFileBetweenTwoCallsIsWhatTheNextCallReads() async throws {
    let url = temporaryWorkbookURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try LocalWorkbook(spreadsheetId: "s", title: "t", tabs: ["B": LocalWorkbook.Tab(cells: ["A1": "seed"])]).write(to: url)
    let client = try LocalWorkbookSheetsClient(file: url)
    #expect(try await client.fetchTab(spreadsheetId: "s", tabName: "B").cell(row: 0, col: 0) == "seed")

    var edited = try LocalWorkbook.load(from: url)
    edited.tabs["B"]?.cells["A1"] = "coach"
    try edited.write(to: url)

    #expect(try await client.fetchTab(spreadsheetId: "s", tabName: "B").cell(row: 0, col: 0) == "coach")
    try await client.write([SheetCellWrite(tabName: "B", row: 1, col: 0, value: "athlete")], spreadsheetId: "s")
    #expect(try LocalWorkbook.load(from: url).tabs["B"]?.cells == ["A1": "coach", "A2": "athlete"])
}
