import Foundation
import Observation
import OSLog

private let sheetPickerLogger = Logger(subsystem: "WorkoutTracker", category: "SheetPicker")

enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    var isSignedIn = false
    private(set) var appearance: AppearancePreference
    private(set) var standardRestDuration: RestDurationSetting
    private(set) var supersetRestDuration: RestDurationSetting
    private(set) var spreadsheetId: String?
    private(set) var spreadsheetTitle: String?
    private let defaults: UserDefaults
    private static let appearanceKey = "appearance"
    private static let standardRestDurationSecondsKey = "standardRestDurationSeconds"
    private static let supersetRestDurationSecondsKey = "supersetRestDurationSeconds"
    private static let spreadsheetIdKey = "spreadsheetId"
    private static let spreadsheetTitleKey = "spreadsheetTitle"
    // Matches both the legacy "advancedToOrder_" and the current "advancedToOrderV2_" override
    // keys (the Session order encoding was re-versioned for 2–6 day Weeks) so prior app state is
    // still recognised regardless of which one is stored.
    private static let currentSessionOverrideKeyPrefix = "advancedToOrder"

    init(defaults: UserDefaults = .standard, hasPriorAppState: Bool = false) {
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
        spreadsheetId = id
        spreadsheetTitle = nil
        defaults.set(id, forKey: Self.spreadsheetIdKey)
        defaults.removeObject(forKey: Self.spreadsheetTitleKey)
        return true
    }

    func setSpreadsheet(id: String, title: String) {
        spreadsheetId = id
        spreadsheetTitle = title
        defaults.set(id, forKey: Self.spreadsheetIdKey)
        defaults.set(title, forKey: Self.spreadsheetTitleKey)
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
        defaults.removeObject(forKey: Self.spreadsheetIdKey)
        defaults.removeObject(forKey: Self.spreadsheetTitleKey)
    }

    private static func loadAppearance(defaults: UserDefaults, hasPriorAppState: Bool) -> AppearancePreference {
        if let preference = defaults.string(forKey: appearanceKey).flatMap(AppearancePreference.init(rawValue:)) {
            return preference
        }

        let seededPreference: AppearancePreference =
            hasPriorAppState || hasStoredAppState(in: defaults) || defaults.object(forKey: appearanceKey) != nil
            ? .dark
            : .system
        defaults.set(seededPreference.rawValue, forKey: appearanceKey)
        return seededPreference
    }

    private static func loadStandardRestDuration(defaults: UserDefaults) -> RestDurationSetting {
        guard defaults.object(forKey: standardRestDurationSecondsKey) != nil else {
            return .standard
        }

        return RestDurationSetting(seconds: defaults.integer(forKey: standardRestDurationSecondsKey))
    }

    private static func loadSupersetRestDuration(defaults: UserDefaults) -> RestDurationSetting {
        guard defaults.object(forKey: supersetRestDurationSecondsKey) != nil else {
            return .superset
        }

        return RestDurationSetting(seconds: defaults.integer(forKey: supersetRestDurationSecondsKey))
    }

    private static func hasStoredAppState(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: spreadsheetIdKey) != nil
            || defaults.object(forKey: spreadsheetTitleKey) != nil
            || defaults.dictionaryRepresentation().keys.contains { key in
                key.hasPrefix(currentSessionOverrideKeyPrefix)
            }
    }
}

enum SettingsSheetSwitchResult: Equatable {
    case switched
    case requiresConfirmation
    case unchanged
    case failed
}

@MainActor
protocol ConfiguredSheetSyncing: AnyObject {
    func sync(spreadsheetId: String) async -> Bool
}

@MainActor
protocol SheetSwitchSyncing: ConfiguredSheetSyncing {
    func hasPendingWrites() throws -> Bool
    func discardPendingWrites() async throws
}

@MainActor
@Observable
final class SettingsSyncActivity {
    private(set) var isSyncInFlight = false

    func run<T>(_ operation: () async -> T) async -> T? {
        guard !isSyncInFlight else { return nil }

        isSyncInFlight = true
        defer { isSyncInFlight = false }

        return await operation()
    }
}

@MainActor
@Observable
final class SettingsManualSyncStore {
    private let settings: SettingsStore
    private let sync: any ConfiguredSheetSyncing
    private let syncActivity: SettingsSyncActivity
    private let onSynced: () -> Void

    init(
        settings: SettingsStore,
        sync: any ConfiguredSheetSyncing,
        syncActivity: SettingsSyncActivity = SettingsSyncActivity(),
        onSynced: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.sync = sync
        self.syncActivity = syncActivity
        self.onSynced = onSynced
    }

    var isSyncInFlight: Bool { syncActivity.isSyncInFlight }

    @discardableResult
    func syncNow() async -> Bool {
        guard let spreadsheetId = settings.spreadsheetId else { return false }

        return await syncActivity.run {
            let didSync = await sync.sync(spreadsheetId: spreadsheetId)
            onSynced()
            return didSync
        } ?? false
    }
}

@MainActor
@Observable
final class SettingsSheetSwitchStore {
    private(set) var pendingConfirmation: SpreadsheetFile?
    private(set) var errorMessage: String?
    private(set) var isSwitching = false

    private let settings: SettingsStore
    private let sync: any SheetSwitchSyncing
    private let syncActivity: SettingsSyncActivity
    private let onSynced: () -> Void

    init(
        settings: SettingsStore,
        sync: any SheetSwitchSyncing,
        syncActivity: SettingsSyncActivity = SettingsSyncActivity(),
        onSynced: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.sync = sync
        self.syncActivity = syncActivity
        self.onSynced = onSynced
    }

    func requestSwitch(to spreadsheet: SpreadsheetFile) async -> SettingsSheetSwitchResult {
        errorMessage = nil
        guard canBeginSwitch else {
            errorMessage = "A sync is already in progress."
            return .failed
        }

        if spreadsheet.spreadsheetId == settings.spreadsheetId {
            settings.setSpreadsheet(id: spreadsheet.spreadsheetId, title: spreadsheet.name)
            return .unchanged
        }

        do {
            guard try !sync.hasPendingWrites() else {
                pendingConfirmation = spreadsheet
                return .requiresConfirmation
            }
        } catch {
            errorMessage = "Couldn't check pending logs. Try again."
            return .failed
        }

        isSwitching = true
        defer { isSwitching = false }
        return await switchNow(to: spreadsheet) ? .switched : .failed
    }

    func confirmPendingSwitch() async -> Bool {
        errorMessage = nil
        guard let spreadsheet = pendingConfirmation else { return false }
        guard canBeginSwitch else {
            errorMessage = "A sync is already in progress."
            return false
        }

        isSwitching = true
        defer { isSwitching = false }

        do {
            try await sync.discardPendingWrites()
        } catch {
            errorMessage = "Couldn't discard pending logs. Try again."
            return false
        }
        pendingConfirmation = nil
        return await switchNow(to: spreadsheet)
    }

    func cancelPendingSwitch() {
        pendingConfirmation = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private var canBeginSwitch: Bool {
        !isSwitching && !syncActivity.isSyncInFlight
    }

    private func switchNow(to spreadsheet: SpreadsheetFile) async -> Bool {
        guard
            let didSync = await syncActivity.run({
                await sync.sync(spreadsheetId: spreadsheet.spreadsheetId)
            })
        else {
            errorMessage = "A sync is already in progress."
            return false
        }

        guard didSync else {
            errorMessage = "Couldn't sync selected sheet. Try again."
            return false
        }
        settings.setSpreadsheet(id: spreadsheet.spreadsheetId, title: spreadsheet.name)
        onSynced()
        return true
    }
}

@MainActor
@Observable
final class SheetPickerStore {
    private(set) var spreadsheets: [SpreadsheetFile] = []
    private(set) var isLoadingList = false
    private(set) var listErrorMessage: String?
    private(set) var validatingSpreadsheetId: String?

    private let client: any SheetsClient
    private let settings: SettingsStore
    private let onValidatedSelection: (SpreadsheetFile) async -> Void
    private var nextPageToken: String?
    private var validationToken: UUID?
    private var rowErrors: [String: String] = [:]

    init(
        client: any SheetsClient,
        settings: SettingsStore,
        onValidatedSelection: ((SpreadsheetFile) async -> Void)? = nil
    ) {
        self.client = client
        self.settings = settings
        self.onValidatedSelection =
            onValidatedSelection ?? { [settings] spreadsheet in
                settings.setSpreadsheet(id: spreadsheet.spreadsheetId, title: spreadsheet.name)
            }
    }

    var canLoadMore: Bool { nextPageToken != nil }

    func loadInitial() async {
        spreadsheets = []
        nextPageToken = nil
        await loadPage(pageToken: nil)
    }

    func loadMore() async {
        guard let nextPageToken else { return }
        await loadPage(pageToken: nextPageToken)
    }

    @discardableResult
    func select(_ spreadsheet: SpreadsheetFile) -> Task<Void, Never> {
        let token = UUID()
        validationToken = token
        validatingSpreadsheetId = spreadsheet.spreadsheetId
        rowErrors[spreadsheet.spreadsheetId] = nil

        return Task { await validate(spreadsheet, token: token) }
    }

    func cancelSelection() {
        validationToken = nil
        validatingSpreadsheetId = nil
    }

    private func validate(_ spreadsheet: SpreadsheetFile, token: UUID) async {
        defer {
            if validationToken == token {
                validationToken = nil
                validatingSpreadsheetId = nil
            }
        }

        do {
            let titles = try await client.listTabTitles(spreadsheetId: spreadsheet.spreadsheetId)
            guard validationToken == token else { return }
            guard titles.contains(where: { blockNumber(from: $0) != nil }) else {
                sheetPickerLogger.error("Validation failed for \(spreadsheet.spreadsheetId): tab titles \(titles)")
                rowErrors[spreadsheet.spreadsheetId] = "No training blocks found in this sheet"
                return
            }

            await onValidatedSelection(spreadsheet)
        } catch {
            guard validationToken == token else { return }
            logAPIError(error, context: "Validation API error for \(spreadsheet.spreadsheetId)")
            rowErrors[spreadsheet.spreadsheetId] = "Couldn't validate this sheet"
        }
    }

    func rowError(for spreadsheet: SpreadsheetFile) -> String? {
        rowErrors[spreadsheet.spreadsheetId]
    }

    private func loadPage(pageToken: String?) async {
        isLoadingList = true
        listErrorMessage = nil
        defer { isLoadingList = false }

        do {
            let page = try await client.listSpreadsheets(pageToken: pageToken)
            spreadsheets += page.spreadsheets
            nextPageToken = page.nextPageToken
        } catch {
            logAPIError(error, context: "Drive list API error")
            listErrorMessage = "Couldn't load sheets"
        }
    }

    private func logAPIError(_ error: Error, context: String) {
        if case SheetsError.http(let statusCode) = error {
            sheetPickerLogger.error("\(context): HTTP \(statusCode)")
            return
        }

        sheetPickerLogger.error("\(context): \(error.localizedDescription)")
    }
}
