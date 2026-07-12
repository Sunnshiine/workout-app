import Foundation
import Testing

@testable import WorkoutTracker

private final class RequestRecorder: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    var data = Data()
    var statusCode = 200

    func load(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (data, statusCode)
    }
}

@Test func listSpreadsheetsParsesSuccessfulDriveResponse() async throws {
    let modifiedTime = "2026-05-27T18:42:31.123Z"
    let recorder = RequestRecorder()
    recorder.data = Data(
        """
        {
          "nextPageToken": "next-token",
          "files": [
            {
              "id": "spreadsheet-id",
              "name": "Training Log",
              "modifiedTime": "\(modifiedTime)"
            }
          ]
        }
        """.utf8
    )
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    let page = try await client.listSpreadsheets(pageToken: nil)
    let expectedDate = try #require(driveModifiedDate(from: modifiedTime))

    #expect(page.nextPageToken == "next-token")
    #expect(page.spreadsheets.count == 1)
    #expect(page.spreadsheets[0].spreadsheetId == "spreadsheet-id")
    #expect(page.spreadsheets[0].name == "Training Log")
    #expect(page.spreadsheets[0].modifiedDate == expectedDate)
}

@Test func listSpreadsheetsForwardsPaginationTokenAndFixedQuery() async throws {
    let recorder = RequestRecorder()
    recorder.data = Data(#"{"files":[]}"#.utf8)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    _ = try await client.listSpreadsheets(pageToken: "older-page")

    let request = try #require(recorder.requests.first)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

    #expect(url.scheme == "https")
    #expect(url.host == "www.googleapis.com")
    #expect(url.path == "/drive/v3/files")
    #expect(query["q"] == "mimeType = 'application/vnd.google-apps.spreadsheet'")
    #expect(query["orderBy"] == "modifiedTime desc")
    #expect(query["pageSize"] == "20")
    #expect(query["fields"] == "nextPageToken,files(id,name,modifiedTime)")
    #expect(query["pageToken"] == "older-page")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

@Test func listSpreadsheetsReturnsEmptyPageWhenDriveHasNoSpreadsheetFiles() async throws {
    let recorder = RequestRecorder()
    recorder.data = Data(#"{"files":[]}"#.utf8)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    let page = try await client.listSpreadsheets(pageToken: nil)

    #expect(page.spreadsheets.isEmpty)
    #expect(page.nextPageToken == nil)
}

@Test func listSpreadsheetsThrowsHTTPErrorForDriveFailure() async throws {
    let recorder = RequestRecorder()
    recorder.statusCode = 403
    recorder.data = Data(#"{"error":{"code":403}}"#.utf8)
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    await #expect(throws: SheetsError.http(403)) {
        _ = try await client.listSpreadsheets(pageToken: nil)
    }
}

@Test func updateCellsSendsMultipleRangesInOneBatchRequest() async throws {
    let recorder = RequestRecorder()
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    try await client.updateCells(
        spreadsheetId: "spreadsheet-id",
        updates: [
            SheetValueRangeUpdate(range: "'Block 27'!K16", values: [["185x5@8"]]),
            SheetValueRangeUpdate(range: "'Block 27'!I15", values: [["8"]])
        ]
    )

    let request = try #require(recorder.requests.first)
    let url = try #require(request.url)
    let bodyData = try #require(request.httpBody)
    let body = try JSONDecoder().decode(RecordedBatchUpdateBody.self, from: bodyData)

    #expect(recorder.requests.count == 1)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(url.scheme == "https")
    #expect(url.host == "sheets.googleapis.com")
    #expect(url.path == "/v4/spreadsheets/spreadsheet-id/values:batchUpdate")
    #expect(body.valueInputOption == "USER_ENTERED")
    #expect(body.data.map(\.range) == ["'Block 27'!K16", "'Block 27'!I15"])
    #expect(body.data.map(\.majorDimension) == ["ROWS", "ROWS"])
    #expect(body.data.map(\.values) == [[["185x5@8"]], [["8"]]])
}

@Test func fetchTabSnapshotRequestsFormattedGridDataAndParsesRowVisibility() async throws {
    let recorder = RequestRecorder()
    recorder.data = Data(
        """
        {
          "sheets": [
            {
              "data": [
                {
                  "startRow": 0,
                  "startColumn": 2,
                  "rowData": [
                    { "values": [{ "formattedValue": "Day 1" }] },
                    { "values": [{ "formattedValue": "Squat" }, { "formattedValue": "2" }] },
                    { "values": [{ "formattedValue": "Bench" }] }
                  ],
                  "rowMetadata": [
                    {},
                    { "hiddenByUser": true },
                    { "hiddenByFilter": true }
                  ]
                }
              ]
            }
          ]
        }
        """.utf8
    )
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: recorder.load)

    let snapshot = try await client.fetchTabSnapshot(spreadsheetId: "spreadsheet-id", tabName: "Block 27")

    let request = try #require(recorder.requests.first)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

    #expect(url.scheme == "https")
    #expect(url.host == "sheets.googleapis.com")
    #expect(url.path == "/v4/spreadsheets/spreadsheet-id")
    #expect(query["includeGridData"] == "true")
    #expect(query["ranges"] == "Block 27")
    #expect(query["fields"]?.contains("formattedValue") == true)
    #expect(query["fields"]?.contains("hiddenByUser") == true)
    #expect(query["fields"]?.contains("hiddenByFilter") == true)
    #expect(snapshot.values.cell(row: 0, col: 2) == "Day 1")
    #expect(snapshot.values.cell(row: 1, col: 2) == "Squat")
    #expect(snapshot.values.cell(row: 1, col: 3) == "2")
    #expect(snapshot.isRowVisible(0) == true)
    #expect(snapshot.isRowVisible(1) == false)
    #expect(snapshot.isRowVisible(2) == false)
    #expect(snapshot.isRowVisible(99) == true)
}

/// Replays a scripted sequence of HTTP status codes so the retry path can be exercised
/// end-to-end through the real client without touching the network.
private final class ScriptedLoader: @unchecked Sendable {
    private var statusCodes: [Int]
    var data: Data
    private(set) var callCount = 0

    init(statusCodes: [Int], data: Data) {
        self.statusCodes = statusCodes
        self.data = data
    }

    func load(_ request: URLRequest) async throws -> (Data, Int) {
        callCount += 1
        // Once a single status remains it repeats, so an "always fails" script is one element.
        let status = statusCodes.count > 1 ? statusCodes.removeFirst() : statusCodes[0]
        return (data, status)
    }
}

@Test func fetchTabSnapshotRetryingBacksOffOnTransientFailuresThenReturnsSnapshot() async throws {
    let loader = ScriptedLoader(
        statusCodes: [429, 503, 200],
        data: Data(#"{"sheets":[{"data":[{"rowData":[{"values":[{"formattedValue":"Squat"}]}]}]}]}"#.utf8)
    )
    let delays = SleepRecorder()
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: loader.load)

    let outcome = try await client.fetchTabSnapshot(
        spreadsheetId: "sid",
        tabName: "Block 27",
        retrying: SheetsBackoff(sleep: delays.record)
    )

    #expect(outcome == .fetched(SheetSnapshot(values: [["Squat"]])))
    #expect(delays.durations == [.seconds(1), .seconds(2)])
    #expect(loader.callCount == 3)
}

@Test func fetchTabSnapshotRetryingFailsTheTabAfterExhaustingBackoff() async throws {
    let loader = ScriptedLoader(statusCodes: [500], data: Data(#"{"sheets":[]}"#.utf8))
    let delays = SleepRecorder()
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: loader.load)

    let outcome = try await client.fetchTabSnapshot(
        spreadsheetId: "sid",
        tabName: "Block 27",
        retrying: SheetsBackoff(sleep: delays.record)
    )

    #expect(outcome == .failed)
    #expect(delays.durations == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
    #expect(loader.callCount == 5)
}

@Test func fetchTabSnapshotRetryingDoesNotRetryAuthFailures() async throws {
    let loader = ScriptedLoader(statusCodes: [403], data: Data(#"{"error":{"code":403}}"#.utf8))
    let delays = SleepRecorder()
    let client = GoogleSheetsClient(tokenProvider: { "token" }, load: loader.load)

    await #expect(throws: SheetsError.http(403)) {
        _ = try await client.fetchTabSnapshot(
            spreadsheetId: "sid",
            tabName: "Block 27",
            retrying: SheetsBackoff(sleep: delays.record)
        )
    }
    #expect(delays.durations.isEmpty)
    #expect(loader.callCount == 1)
}

/// Records requested backoff delays without sleeping on the wall clock.
private final class SleepRecorder: @unchecked Sendable {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) async throws {
        durations.append(duration)
    }
}

private func driveModifiedDate(from value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

private struct RecordedBatchUpdateBody: Decodable {
    let valueInputOption: String
    let data: [RecordedValueRange]
}

private struct RecordedValueRange: Decodable {
    let range: String
    let majorDimension: String
    let values: [[String]]
}
