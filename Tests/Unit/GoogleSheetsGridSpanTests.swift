import Foundation
import Testing

@testable import WorkoutTracker

private func snapshot(fromSheetsJSON json: String) async throws -> SheetSnapshot {
    let data = Data(json.utf8)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: { _ in (data, 200) })
    return try await client.fetchTabSnapshot(spreadsheetId: "sid", tabName: "Block 27")
}

@Test func spanWithoutStartRowOrStartColumnBeginsAtTheTopLeftCell() async throws {
    let snapshot = try await snapshot(
        fromSheetsJSON: #"{"sheets":[{"data":[{"rowData":[{"values":[{"formattedValue":"Squat"}]}]}]}]}"#
    )

    #expect(snapshot.values == [["Squat"]])
    #expect(snapshot.rowVisibility == [:])
}

@Test func spansAreAssembledIntoOneGridEachAtItsOwnOffset() async throws {
    let snapshot = try await snapshot(
        fromSheetsJSON: """
            {
              "sheets": [
                {
                  "data": [
                    { "rowData": [{ "values": [{ "formattedValue": "A1" }] }] },
                    {
                      "startRow": 2,
                      "startColumn": 1,
                      "rowData": [{ "values": [{ "formattedValue": "B3" }, { "formattedValue": "C3" }] }],
                      "rowMetadata": [{ "hiddenByUser": true }]
                    }
                  ]
                },
                { "data": [{ "startRow": 1, "rowData": [{ "values": [{ "formattedValue": "A2" }] }] }] }
              ]
            }
            """
    )

    #expect(snapshot.values == [["A1"], ["A2"], ["", "B3", "C3"]])
    #expect(snapshot.rowVisibility == [2: SheetRowVisibility(hiddenByUser: true)])
}

@Test func spanWithoutRowDataOrRowMetadataContributesNothing() async throws {
    let snapshot = try await snapshot(fromSheetsJSON: #"{"sheets":[{"data":[{"startRow":5,"startColumn":5}]}]}"#)

    #expect(snapshot.values == [])
    #expect(snapshot.rowVisibility == [:])
}

@Test func rowWithoutValuesAndCellWithoutFormattedValueReadAsEmpty() async throws {
    let snapshot = try await snapshot(
        fromSheetsJSON: """
            {
              "sheets": [
                {
                  "data": [
                    {
                      "rowData": [
                        {},
                        { "values": [{}, { "formattedValue": "B2" }] },
                        { "values": [] }
                      ]
                    }
                  ]
                }
              ]
            }
            """
    )

    #expect(snapshot.values == [[], ["", "B2"], []])
}

@Test func rowMetadataMarksOnlyTheRowsTheSpanReportsHidden() async throws {
    let snapshot = try await snapshot(
        fromSheetsJSON: """
            {
              "sheets": [
                {
                  "data": [
                    {
                      "startRow": 3,
                      "rowMetadata": [
                        {},
                        { "hiddenByUser": false, "hiddenByFilter": false },
                        { "hiddenByFilter": true },
                        { "hiddenByUser": true, "hiddenByFilter": true }
                      ]
                    }
                  ]
                }
              ]
            }
            """
    )

    #expect(
        snapshot.rowVisibility == [
            5: SheetRowVisibility(hiddenByFilter: true),
            6: SheetRowVisibility(hiddenByUser: true, hiddenByFilter: true)
        ]
    )
}

@Test func sheetsResponseWithoutDataYieldsAnEmptySnapshot() async throws {
    let snapshot = try await snapshot(fromSheetsJSON: #"{"sheets":[{}]}"#)

    #expect(snapshot == SheetSnapshot(values: []))
}
