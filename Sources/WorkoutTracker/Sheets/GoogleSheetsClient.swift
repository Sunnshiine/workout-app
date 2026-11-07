import Foundation

private struct GoogleSheetsListResponse: Decodable {
    let sheets: [GoogleSheetsListSheet]
}

private struct GoogleSheetsListSheet: Decodable {
    let properties: GoogleSheetsListProperties
}

private struct GoogleSheetsListProperties: Decodable {
    let title: String
}

private struct GoogleSheetsSnapshotResponse: Decodable {
    let sheets: [GoogleSheetsSnapshotSheet]
}

private struct GoogleSheetsSnapshotSheet: Decodable {
    let data: [GoogleSheetsGridData]?
}

/// One rectangular span of a Sheet as the API returns it.
///
/// Google omits every field it has nothing to say about, so each one is optional on the wire. The
/// accessors resolve the documented default once, here, and the snapshot walkers read only those.
private struct GoogleSheetsGridData: Decodable {
    let startRow: Int?
    let startColumn: Int?
    let rowData: [GoogleSheetsRowData]?
    let rowMetadata: [GoogleSheetsDimensionProperties]?

    var firstRow: Int { startRow ?? 0 }
    var firstColumn: Int { startColumn ?? 0 }
    var rows: [GoogleSheetsRowData] { rowData ?? [] }
    var metadata: [GoogleSheetsDimensionProperties] { rowMetadata ?? [] }
}

private struct GoogleSheetsRowData: Decodable {
    let values: [GoogleSheetsCellData]?

    var cellText: [String] { (values ?? []).map { $0.formattedValue ?? "" } }
}

private struct GoogleSheetsCellData: Decodable {
    let formattedValue: String?
    let note: String?
}

private struct GoogleSheetsDimensionProperties: Decodable {
    let hiddenByUser: Bool?
    let hiddenByFilter: Bool?

    var visibility: SheetRowVisibility {
        SheetRowVisibility(hiddenByUser: hiddenByUser ?? false, hiddenByFilter: hiddenByFilter ?? false)
    }
}

private struct GoogleSheetsValueRange: Encodable {
    let range: String
    let majorDimension: String
    let values: [[String]]
}

private struct GoogleSheetsBatchUpdateBody: Encodable {
    let valueInputOption: String
    let data: [GoogleSheetsValueRange]
}

private struct GoogleSheetsTabIdsResponse: Decodable {
    struct Sheet: Decodable {
        let properties: Properties
    }

    /// Google leaves out a field at its default, so the id of a tab whose id is 0 can read as absent.
    struct Properties: Decodable {
        let sheetId: Int?
        let title: String
    }

    let sheets: [Sheet]
}

/// `spreadsheets:batchUpdate` with one `updateCells` request. `fields: "note"` is what keeps the
/// cell's value out of the write.
private struct GoogleSheetsCellNoteBody: Encodable {
    struct Request: Encodable {
        let updateCells: UpdateCells
    }

    struct UpdateCells: Encodable {
        let rows: [Row]
        let fields = "note"
        let start: Start
    }

    struct Row: Encodable {
        let values: [Cell]
    }

    struct Cell: Encodable {
        let note: String
    }

    struct Start: Encodable {
        let sheetId: Int
        let rowIndex: Int
        let columnIndex: Int
    }

    let requests: [Request]

    init(note: SheetCellNoteWrite, sheetId: Int) {
        requests = [
            Request(
                updateCells: UpdateCells(
                    rows: [Row(values: [Cell(note: note.text)])],
                    start: Start(sheetId: sheetId, rowIndex: note.row, columnIndex: note.col)
                )
            )
        ]
    }
}

private struct GoogleDriveFilesResponse: Decodable {
    let nextPageToken: String?
    let files: [GoogleDriveFile]
}

private struct GoogleDriveFile: Decodable {
    let id: String
    let name: String
    let modifiedTime: String
}

private enum GoogleDriveListQuery {
    static let endpoint = "https://www.googleapis.com/drive/v3/files"
    static let spreadsheetMimeType = "application/vnd.google-apps.spreadsheet"
    static let pageSize = 20
}

struct GoogleSheetsClient: SheetsClient {
    private let tokenProvider: @Sendable () async throws -> String
    private let load: @Sendable (URLRequest) async throws -> (Data, Int)

    init(
        tokenProvider: @escaping @Sendable () async throws -> String = GoogleSheetsClient.defaultToken,
        load: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = GoogleSheetsClient.loadWithURLSession
    ) {
        self.tokenProvider = tokenProvider
        self.load = load
    }

    /// The sheet-picker client for the running environment: the fixture application's own drive
    /// under UI-test launch arguments, otherwise a live `GoogleSheetsClient`. Centralises the
    /// fixture/live decision so every sheet-picker entry point (Onboarding and Settings) shares one
    /// source.
    @MainActor
    static func forCurrentEnvironment() -> any SheetsClient {
        #if DEBUG
            if UITestFixture.isEnabled {
                return UITestFixture.sheets
            }
        #endif
        return GoogleSheetsClient()
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        guard
            let url = URL(
                string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)?fields=sheets.properties.title"
            )
        else {
            throw SheetsError.malformedResponse
        }
        let data = try await get(url)
        return (try JSONDecoder().decode(GoogleSheetsListResponse.self, from: data)).sheets.map { $0.properties.title }
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        var components = URLComponents(string: GoogleDriveListQuery.endpoint)
        components?.queryItems = [
            URLQueryItem(name: "q", value: "mimeType = '\(GoogleDriveListQuery.spreadsheetMimeType)'"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "pageSize", value: String(GoogleDriveListQuery.pageSize)),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,modifiedTime)")
        ]
        if let pageToken {
            components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        guard let url = components?.url else {
            throw SheetsError.malformedResponse
        }

        let data = try await get(url)
        let response = try JSONDecoder().decode(GoogleDriveFilesResponse.self, from: data)
        let spreadsheets = try response.files.map { file in
            guard let modifiedDate = GoogleSheetsClient.driveModifiedDate(from: file.modifiedTime) else {
                throw SheetsError.malformedResponse
            }
            return SpreadsheetFile(name: file.name, spreadsheetId: file.id, modifiedDate: modifiedDate)
        }
        return SpreadsheetListPage(spreadsheets: spreadsheets, nextPageToken: response.nextPageToken)
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        var components = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)")
        components?.queryItems = [
            URLQueryItem(name: "includeGridData", value: "true"),
            URLQueryItem(name: "ranges", value: tabName),
            URLQueryItem(
                name: "fields",
                value: "sheets(data(startRow,startColumn,rowData(values(formattedValue,note)),rowMetadata(hiddenByUser,hiddenByFilter)))"
            )
        ]
        guard let url = components?.url else {
            throw SheetsError.malformedResponse
        }
        let data = try await get(url)
        let response = try JSONDecoder().decode(GoogleSheetsSnapshotResponse.self, from: data)
        return Self.snapshot(from: response)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
        guard !cells.isEmpty else { return }
        guard
            let url = URL(
                string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values:batchUpdate"
            )
        else {
            throw SheetsError.malformedResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            GoogleSheetsBatchUpdateBody(
                valueInputOption: "USER_ENTERED",
                data: cells.map { cell in
                    GoogleSheetsValueRange(
                        range: singleCellRange(tabName: cell.tabName, row: cell.row, col: cell.col),
                        majorDimension: "ROWS",
                        values: [[cell.value]]
                    )
                }
            )
        )

        let (_, statusCode) = try await load(req)
        guard (200..<300).contains(statusCode) else { throw SheetsError.http(statusCode) }
    }

    func writeCellNote(_ note: SheetCellNoteWrite, spreadsheetId: String) async throws {
        let sheetId = try await sheetId(ofTab: note.tabName, spreadsheetId: spreadsheetId)
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate") else {
            throw SheetsError.malformedResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(GoogleSheetsCellNoteBody(note: note, sheetId: sheetId))

        let (_, statusCode) = try await load(req)
        guard (200..<300).contains(statusCode) else { throw SheetsError.http(statusCode) }
    }

    /// `updateCells` addresses a tab by its numeric id, which nothing else in the app has a use for.
    private func sheetId(ofTab tabName: String, spreadsheetId: String) async throws -> Int {
        var components = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)")
        components?.queryItems = [URLQueryItem(name: "fields", value: "sheets.properties(sheetId,title)")]
        guard let url = components?.url else {
            throw SheetsError.malformedResponse
        }
        let response = try JSONDecoder().decode(GoogleSheetsTabIdsResponse.self, from: try await get(url))
        guard let tab = response.sheets.first(where: { $0.properties.title == tabName }) else {
            throw SheetsError.malformedResponse
        }
        return tab.properties.sheetId ?? 0
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        let (data, statusCode) = try await load(req)
        guard (200..<300).contains(statusCode) else { throw SheetsError.http(statusCode) }
        return data
    }

    private static func driveModifiedDate(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func snapshot(from response: GoogleSheetsSnapshotResponse) -> SheetSnapshot {
        let gridData = response.sheets.flatMap { $0.data ?? [] }
        return SheetSnapshot(
            values: valuesGrid(from: gridData),
            rowVisibility: rowVisibility(from: gridData),
            cellNotes: cellNotes(from: gridData)
        )
    }

    /// The cell grid the spans describe, each span's rows placed at its own start row and column.
    private static func valuesGrid(from gridData: [GoogleSheetsGridData]) -> SheetGrid {
        var values: SheetGrid = []
        for span in gridData {
            values.write(span.rows.map(\.cellText), atRow: span.firstRow, col: span.firstColumn)
        }
        return values
    }

    private static func cellNotes(from gridData: [GoogleSheetsGridData]) -> [String: String] {
        var notes: [String: String] = [:]
        for span in gridData {
            for (rowOffset, row) in span.rows.enumerated() {
                for (colOffset, cell) in (row.values ?? []).enumerated() {
                    guard let note = cell.note else { continue }
                    notes[indexToA1(row: span.firstRow + rowOffset, col: span.firstColumn + colOffset)] = note
                }
            }
        }
        return notes
    }

    /// The rows the spans report as hidden, keyed by row index. A fully visible row is left out.
    private static func rowVisibility(from gridData: [GoogleSheetsGridData]) -> [Int: SheetRowVisibility] {
        var rowVisibility: [Int: SheetRowVisibility] = [:]
        for span in gridData {
            for (rowOffset, row) in span.metadata.enumerated() where !row.visibility.isVisible {
                rowVisibility[span.firstRow + rowOffset] = row.visibility
            }
        }
        return rowVisibility
    }

    private static func defaultToken() async throws -> String {
        #if canImport(GoogleSignIn)
            return try await GoogleAuth.accessToken()
        #else
            throw SheetsError.notAuthorized
        #endif
    }

    private static func loadWithURLSession(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SheetsError.malformedResponse
        }
        return (data, http.statusCode)
    }
}
