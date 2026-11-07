import Foundation
import Testing

@testable import WorkoutTracker

/// Answers the tab-id read and records every request, so a test pins the exact bytes Google receives.
private final class CellNoteRecorder: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let tabIds: String
    private let writeStatus: Int

    init(tabIds: String, writeStatus: Int = 200) {
        self.tabIds = tabIds
        self.writeStatus = writeStatus
    }

    func load(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return request.httpMethod == "POST" ? (Data("{}".utf8), writeStatus) : (Data(tabIds.utf8), 200)
    }
}

private let twoTabs = #"{"sheets":[{"properties":{"sheetId":0,"title":"Overview"}},{"properties":{"sheetId":1874,"title":"Block 27"}}]}"#

private func note(text: String = "Coach: brace\nSet 2 · Pain: left hip") -> SheetCellNoteWrite {
    SheetCellNoteWrite(tabName: "Block 27", row: 14, col: 10, text: text)
}

@Test func aCellNoteWriteSendsTheShapeGoogleDocumentsForUpdateCells() async throws {
    let recorder = CellNoteRecorder(tabIds: twoTabs)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    try await client.writeCellNote(note(), spreadsheetId: "spreadsheet-id")

    let request = try #require(recorder.requests.last)
    #expect(request.url?.absoluteString == "https://sheets.googleapis.com/v4/spreadsheets/spreadsheet-id:batchUpdate")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? NSDictionary
    let expected: NSDictionary = [
        "requests": [
            [
                "updateCells": [
                    "rows": [["values": [["note": "Coach: brace\nSet 2 · Pain: left hip"]]]],
                    "fields": "note",
                    "start": ["sheetId": 1874, "rowIndex": 14, "columnIndex": 10]
                ]
            ]
        ]
    ]
    #expect(body == expected)
}

@Test func aCellNoteWriteFindsTheTabsIdByItsTitleWithoutReadingAnythingElse() async throws {
    let recorder = CellNoteRecorder(tabIds: twoTabs)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    try await client.writeCellNote(note(), spreadsheetId: "spreadsheet-id")

    #expect(recorder.requests.count == 2)
    let read = try #require(recorder.requests.first)
    #expect(read.httpMethod == "GET")
    let components = try #require(read.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
    #expect(components.path == "/v4/spreadsheets/spreadsheet-id")
    #expect(components.queryItems == [URLQueryItem(name: "fields", value: "sheets.properties(sheetId,title)")])
}

@Test func aFirstTabWhoseIdGoogleLeavesOutIsTabZero() async throws {
    let recorder = CellNoteRecorder(tabIds: #"{"sheets":[{"properties":{"title":"Block 27"}}]}"#)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    try await client.writeCellNote(note(), spreadsheetId: "spreadsheet-id")

    let body = try #require(try recorder.requests.last?.httpBody.map { try JSONSerialization.jsonObject(with: $0) } as? [String: Any])
    let requests = try #require(body["requests"] as? [[String: [String: Any]]])
    let start = try #require(requests.first?["updateCells"]?["start"] as? [String: Int])
    #expect(start == ["sheetId": 0, "rowIndex": 14, "columnIndex": 10])
}

@Test func aTabThatIsGoneWritesNothing() async throws {
    let recorder = CellNoteRecorder(tabIds: #"{"sheets":[{"properties":{"sheetId":3,"title":"Block 28"}}]}"#)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    await #expect(throws: SheetsError.malformedResponse) {
        try await client.writeCellNote(note(), spreadsheetId: "spreadsheet-id")
    }
    #expect(recorder.requests.count == 1)
}

@Test func aFailedCellNoteWriteThrowsSoTheFlagStaysQueued() async throws {
    let recorder = CellNoteRecorder(tabIds: twoTabs, writeStatus: 403)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    await #expect(throws: SheetsError.http(403)) {
        try await client.writeCellNote(note(), spreadsheetId: "spreadsheet-id")
    }
}

@Test func theSheetReadAsksForNotesAndPlacesEachAtItsOwnCell() async throws {
    let requests = RequestLog()
    let response = """
        {"sheets":[{"data":[{"startRow":14,"startColumn":10,"rowData":[
          {"values":[{"formattedValue":"185x5@8","note":"Set 1 · Pain"},{"formattedValue":"7"}]},
          {"values":[{},{"note":"Coach: brace"}]}
        ]}]}]}
        """
    let client = GoogleSheetsClient(
        tokenProvider: { "token" },
        load: { request in
            requests.append(request)
            return (Data(response.utf8), 200)
        }
    )

    let snapshot = try await client.fetchTabSnapshot(spreadsheetId: "spreadsheet-id", tabName: "Block 27")

    #expect(snapshot.cellNotes == ["K15": "Set 1 · Pain", "L16": "Coach: brace"])
    #expect(snapshot.values.cell(row: 14, col: 10) == "185x5@8")
    let query = requests.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
    let fields = query?.first { $0.name == "fields" }?.value
    #expect(fields == "sheets(data(startRow,startColumn,rowData(values(formattedValue,note)),rowMetadata(hiddenByUser,hiddenByFilter)))")
}

private final class RequestLog: @unchecked Sendable {
    private(set) var first: URLRequest?

    func append(_ request: URLRequest) {
        if first == nil { first = request }
    }
}
