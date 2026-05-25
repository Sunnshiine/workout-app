import Foundation

@MainActor
@Observable
final class SettingsStore {
    var isSignedIn = false
    private(set) var spreadsheetId: String?
    private let defaults: UserDefaults
    private let key = "spreadsheetId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.spreadsheetId = defaults.string(forKey: key)
    }

    var isConfigured: Bool { isSignedIn && spreadsheetId != nil }

    /// Stores the spreadsheet id parsed from a pasted Sheet URL. Returns false if unparseable.
    @discardableResult
    func setSheetURL(_ url: String) -> Bool {
        guard let id = extractSpreadsheetId(from: url) else { return false }
        spreadsheetId = id
        defaults.set(id, forKey: key)
        return true
    }
}
