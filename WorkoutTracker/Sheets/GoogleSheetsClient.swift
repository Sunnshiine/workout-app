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

private struct GoogleSheetValuesResponse: Decodable {
    let values: [[String]]?
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

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        let range = tabName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tabName
        let urlString =
            "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(range)"
            + "?valueRenderOption=FORMATTED_VALUE&majorDimension=ROWS"
        guard
            let url = URL(
                string: urlString
            )
        else {
            throw SheetsError.malformedResponse
        }
        let data = try await get(url)
        return (try JSONDecoder().decode(GoogleSheetValuesResponse.self, from: data)).values ?? []
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
