import Observation

@MainActor
@Observable
final class SettingsStore {
    var isSignedIn = false
    private(set) var appearance: AppearancePreference
    private(set) var standardRestDuration: RestDurationSetting
    private(set) var supersetRestDuration: RestDurationSetting
    private(set) var spreadsheetId: String?
    private(set) var spreadsheetTitle: String?
    private let defaults: AppDefaults
    private static let appearanceKey = "appearance"
    private static let standardRestDurationSecondsKey = "standardRestDurationSeconds"
    private static let supersetRestDurationSecondsKey = "supersetRestDurationSeconds"
    private static let spreadsheetIdKey = "spreadsheetId"
    private static let spreadsheetTitleKey = "spreadsheetTitle"
    // Matches both the legacy "advancedToOrder_" and the current "advancedToOrderV2_" override
    // keys (the Session order encoding was re-versioned for 2–6 day Weeks) so prior app state is
    // still recognised regardless of which one is stored.
    private static let currentSessionOverrideKeyPrefix = "advancedToOrder"

    init(defaults: AppDefaults, hasPriorAppState: Bool = false) {
        self.defaults = defaults
        self.spreadsheetId = defaults.string(forKey: Self.spreadsheetIdKey)
        self.spreadsheetTitle = defaults.string(forKey: Self.spreadsheetTitleKey)
        self.appearance = Self.loadAppearance(defaults: defaults, hasPriorAppState: hasPriorAppState)
        self.standardRestDuration = Self.loadStandardRestDuration(defaults: defaults)
        self.supersetRestDuration = Self.loadSupersetRestDuration(defaults: defaults)
    }

    var isConfigured: Bool { isSignedIn && spreadsheetId != nil }

    /// Stores the spreadsheet id parsed from a pasted Sheet URL. Returns false if unparseable.
    @discardableResult
    func setSheetURL(_ url: String) -> Bool {
        guard let id = extractSpreadsheetId(from: url) else { return false }
        setSpreadsheet(id: id)
        return true
    }

    func setSpreadsheet(id: String, title: String) {
        spreadsheetId = id
        spreadsheetTitle = title
        defaults.set(id, forKey: Self.spreadsheetIdKey)
        defaults.set(title, forKey: Self.spreadsheetTitleKey)
    }

    /// Commits a spreadsheet selection without a known title (e.g. from a pasted URL), clearing
    /// any previously stored title so a stale title can't linger against the new selection.
    func setSpreadsheet(id: String) {
        spreadsheetId = id
        spreadsheetTitle = nil
        defaults.set(id, forKey: Self.spreadsheetIdKey)
        defaults.removeValue(forKey: Self.spreadsheetTitleKey)
    }

    func setAppearance(_ preference: AppearancePreference) {
        appearance = preference
        defaults.set(preference.rawValue, forKey: Self.appearanceKey)
    }

    func setStandardRestDuration(_ duration: RestDurationSetting) {
        standardRestDuration = duration
        defaults.set(duration.seconds, forKey: Self.standardRestDurationSecondsKey)
    }

    func setSupersetRestDuration(_ duration: RestDurationSetting) {
        supersetRestDuration = duration
        defaults.set(duration.seconds, forKey: Self.supersetRestDurationSecondsKey)
    }

    func signOut() {
        isSignedIn = false
        clearSpreadsheet()
    }

    private func clearSpreadsheet() {
        spreadsheetId = nil
        spreadsheetTitle = nil
        defaults.removeValue(forKey: Self.spreadsheetIdKey)
        defaults.removeValue(forKey: Self.spreadsheetTitleKey)
    }

    private static func loadAppearance(defaults: AppDefaults, hasPriorAppState: Bool) -> AppearancePreference {
        if let preference = defaults.string(forKey: appearanceKey).flatMap(AppearancePreference.init(rawValue:)) {
            return preference
        }

        let seededPreference: AppearancePreference =
            hasPriorAppState || hasStoredAppState(in: defaults) || defaults.hasValue(forKey: appearanceKey)
            ? .dark
            : .system
        defaults.set(seededPreference.rawValue, forKey: appearanceKey)
        return seededPreference
    }

    private static func loadStandardRestDuration(defaults: AppDefaults) -> RestDurationSetting {
        defaults.integer(forKey: standardRestDurationSecondsKey).map(RestDurationSetting.init(seconds:)) ?? .standard
    }

    private static func loadSupersetRestDuration(defaults: AppDefaults) -> RestDurationSetting {
        defaults.integer(forKey: supersetRestDurationSecondsKey).map(RestDurationSetting.init(seconds:)) ?? .superset
    }

    private static func hasStoredAppState(in defaults: AppDefaults) -> Bool {
        defaults.hasValue(forKey: spreadsheetIdKey)
            || defaults.hasValue(forKey: spreadsheetTitleKey)
            || defaults.keys.contains { key in
                key.hasPrefix(currentSessionOverrideKeyPrefix)
            }
    }
}
