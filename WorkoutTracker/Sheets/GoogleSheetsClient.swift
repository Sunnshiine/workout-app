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

private struct GoogleSheetsGridData: Decodable {
    let startRow: Int?
    let startColumn: Int?
    let rowData: [GoogleSheetsRowData]?
    let rowMetadata: [GoogleSheetsDimensionProperties]?
}

private struct GoogleSheetsRowData: Decodable {
    let values: [GoogleSheetsCellData]?
}

private struct GoogleSheetsCellData: Decodable {
    let formattedValue: String?
}

private struct GoogleSheetsDimensionProperties: Decodable {
    let hiddenByUser: Bool?
    let hiddenByFilter: Bool?
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

    /// The sheet-picker client for the running environment: a deterministic fixture client under
    /// UI-test launch arguments, otherwise a live `GoogleSheetsClient`. Centralises the fixture/live
    /// decision so every sheet-picker entry point (Onboarding and Settings) shares one source.
    static func forCurrentEnvironment() -> any SheetsClient {
        #if DEBUG
            if UITestFixture.isEnabled {
                return UITestFixture.makeSheetsClient()
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
                value: "sheets(data(startRow,startColumn,rowData(values(formattedValue)),rowMetadata(hiddenByUser,hiddenByFilter)))"
            )
        ]
        guard let url = components?.url else {
            throw SheetsError.malformedResponse
        }
        let data = try await get(url)
        let response = try JSONDecoder().decode(GoogleSheetsSnapshotResponse.self, from: data)
        return Self.snapshot(from: response)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        try await updateCells(
            spreadsheetId: spreadsheetId,
            updates: [SheetValueRangeUpdate(range: range, values: values)]
        )
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        guard !updates.isEmpty else { return }
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
                data: updates.map { update in
                    GoogleSheetsValueRange(range: update.range, majorDimension: "ROWS", values: update.values)
                }
            )
        )

        let (_, statusCode) = try await load(req)
        guard (200..<300).contains(statusCode) else { throw SheetsError.http(statusCode) }
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
        var values: SheetGrid = []
        var rowVisibility: [Int: SheetRowVisibility] = [:]

        for gridData in response.sheets.flatMap({ $0.data ?? [] }) {
            let startRow = gridData.startRow ?? 0
            let startColumn = gridData.startColumn ?? 0

            for (rowOffset, rowData) in (gridData.rowData ?? []).enumerated() {
                let rowIndex = startRow + rowOffset
                let formattedValues = (rowData.values ?? []).map { $0.formattedValue ?? "" }
                values = applying(formattedValues, atRow: rowIndex, startColumn: startColumn, to: values)
            }

            for (rowOffset, metadata) in (gridData.rowMetadata ?? []).enumerated() {
                let visibility = SheetRowVisibility(
                    hiddenByUser: metadata.hiddenByUser ?? false,
                    hiddenByFilter: metadata.hiddenByFilter ?? false
                )
                if visibility != SheetRowVisibility() {
                    rowVisibility[startRow + rowOffset] = visibility
                }
            }
        }

        return SheetSnapshot(values: values, rowVisibility: rowVisibility)
    }

    private static func applying(
        _ rowValues: [String],
        atRow rowIndex: Int,
        startColumn: Int,
        to grid: SheetGrid
    ) -> SheetGrid {
        var updated = grid
        if rowIndex >= updated.count {
            updated.append(contentsOf: SheetGrid(repeating: [], count: rowIndex - updated.count + 1))
        }
        let requiredColumns = startColumn + rowValues.count
        if requiredColumns > updated[rowIndex].count {
            updated[rowIndex].append(
                contentsOf: [String](repeating: "", count: requiredColumns - updated[rowIndex].count)
            )
        }
        for (offset, value) in rowValues.enumerated() {
            updated[rowIndex][startColumn + offset] = value
        }
        return updated
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
