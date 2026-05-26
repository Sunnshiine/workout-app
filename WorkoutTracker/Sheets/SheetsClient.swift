import Foundation

protocol SheetsClient: Sendable {
    func listTabTitles(spreadsheetId: String) async throws -> [String]
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid
}

enum SheetsError: Error, Equatable {
    case notAuthorized
    case http(Int)
    case malformedResponse
}

func extractSpreadsheetId(from url: String) -> String? {
    guard let range = url.range(of: "/spreadsheets/d/") else { return nil }
    let rest = url[range.upperBound...]
    let id = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
    return id.isEmpty ? nil : String(id)
}
