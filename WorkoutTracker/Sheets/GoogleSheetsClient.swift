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

struct GoogleSheetsClient: SheetsClient {
    private let tokenProvider: @Sendable () async throws -> String

    init(tokenProvider: @escaping @Sendable () async throws -> String = { try await GoogleAuth.accessToken() }) {
        self.tokenProvider = tokenProvider
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
                data: [GoogleSheetsValueRange(range: range, majorDimension: "ROWS", values: values)]
            )
        )

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SheetsError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw SheetsError.http(http.statusCode) }
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SheetsError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw SheetsError.http(http.statusCode) }
        return data
    }
}
