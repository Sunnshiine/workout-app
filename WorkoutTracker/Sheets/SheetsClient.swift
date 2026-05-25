import Foundation

func extractSpreadsheetId(from url: String) -> String? {
    guard let range = url.range(of: "/spreadsheets/d/") else { return nil }
    let rest = url[range.upperBound...]
    let id = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
    return id.isEmpty ? nil : String(id)
}
