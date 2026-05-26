import Foundation

struct GoogleSheetsClient: SheetsClient {
    private let tokenProvider: @Sendable () async throws -> String

    init(tokenProvider: @escaping @Sendable () async throws -> String = { try await GoogleAuth.accessToken() }) {
        self.tokenProvider = tokenProvider
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)?fields=sheets.properties.title")!
        let data = try await get(url)
        struct Resp: Decodable {
            struct S: Decodable {
                struct P: Decodable { let title: String }
                let properties: P
            }
            let sheets: [S]
        }
        return (try JSONDecoder().decode(Resp.self, from: data)).sheets.map { $0.properties.title }
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        let range = tabName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tabName
        let url = URL(
            string:
                "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(range)?valueRenderOption=FORMATTED_VALUE&majorDimension=ROWS"
        )!
        let data = try await get(url)
        struct Resp: Decodable { let values: [[String]]? }
        return (try JSONDecoder().decode(Resp.self, from: data)).values ?? []
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values:batchUpdate")!
        struct ValueRange: Encodable {
            let range: String
            let majorDimension: String
            let values: [[String]]
        }
        struct Body: Encodable {
            let valueInputOption: String
            let data: [ValueRange]
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            Body(
                valueInputOption: "USER_ENTERED",
                data: [ValueRange(range: range, majorDimension: "ROWS", values: values)]
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
