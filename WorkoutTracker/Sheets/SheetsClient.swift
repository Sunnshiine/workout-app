import Foundation

struct SheetValueRangeUpdate: Sendable, Equatable {
    let range: String
    let values: [[String]]
}

protocol SheetsClient: Sendable {
    func listTabTitles(spreadsheetId: String) async throws -> [String]
    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws
    /// Throws unless callers can treat every update as applied.
    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws
}

extension SheetsClient {
    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        throw SheetsError.malformedResponse
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        try await fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName).values
    }

    /// Fetches a tab under the fill's retry policy, reporting a `.failed` tab as a first-class
    /// outcome (ADR-0012) rather than a thrown error the caller might silently skip. Applies the
    /// backoff schedule around `fetchTabSnapshot`, so every conformer gains it without bespoke logic.
    func fetchTabSnapshot(
        spreadsheetId: String,
        tabName: String,
        retrying backoff: SheetsBackoff = SheetsBackoff()
    ) async throws -> TabFetchOutcome {
        try await backoff.fetch {
            try await fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName)
        }
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        guard updates.count <= 1 else {
            throw SheetsError.unsupportedBatchUpdate
        }
        if let update = updates.first {
            try await updateCells(spreadsheetId: spreadsheetId, range: update.range, values: update.values)
        }
    }
}

struct SpreadsheetListPage: Equatable, Sendable {
    let spreadsheets: [SpreadsheetFile]
    let nextPageToken: String?
}

struct SpreadsheetFile: Equatable, Sendable {
    let name: String
    let spreadsheetId: String
    let modifiedDate: Date
}

enum SheetsError: Error, Equatable {
    case notAuthorized
    case http(Int)
    case malformedResponse
    case unsupportedBatchUpdate
}

func extractSpreadsheetId(from url: String) -> String? {
    guard let range = url.range(of: "/spreadsheets/d/") else { return nil }
    let rest = url[range.upperBound...]
    let id = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
    return id.isEmpty ? nil : String(id)
}
