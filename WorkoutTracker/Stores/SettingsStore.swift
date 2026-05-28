import Foundation
import Observation
import OSLog

private let sheetPickerLogger = Logger(subsystem: "WorkoutTracker", category: "SheetPicker")

@MainActor
@Observable
final class SettingsStore {
    var isSignedIn = false
    private(set) var spreadsheetId: String?
    private(set) var spreadsheetTitle: String?
    private let defaults: UserDefaults
    private let spreadsheetIdKey = "spreadsheetId"
    private let spreadsheetTitleKey = "spreadsheetTitle"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.spreadsheetId = defaults.string(forKey: spreadsheetIdKey)
        self.spreadsheetTitle = defaults.string(forKey: spreadsheetTitleKey)
    }

    var isConfigured: Bool { isSignedIn && spreadsheetId != nil }

    /// Stores the spreadsheet id parsed from a pasted Sheet URL. Returns false if unparseable.
    @discardableResult
    func setSheetURL(_ url: String) -> Bool {
        guard let id = extractSpreadsheetId(from: url) else { return false }
        spreadsheetId = id
        spreadsheetTitle = nil
        defaults.set(id, forKey: spreadsheetIdKey)
        defaults.removeObject(forKey: spreadsheetTitleKey)
        return true
    }

    func setSpreadsheet(id: String, title: String) {
        spreadsheetId = id
        spreadsheetTitle = title
        defaults.set(id, forKey: spreadsheetIdKey)
        defaults.set(title, forKey: spreadsheetTitleKey)
    }

    func signOut() {
        isSignedIn = false
        clearSpreadsheet()
    }

    private func clearSpreadsheet() {
        spreadsheetId = nil
        spreadsheetTitle = nil
        defaults.removeObject(forKey: spreadsheetIdKey)
        defaults.removeObject(forKey: spreadsheetTitleKey)
    }
}

enum SettingsSheetSwitchResult: Equatable {
    case switched
    case requiresConfirmation
    case unchanged
    case failed
}

@MainActor
protocol SheetSwitchSyncing: AnyObject {
    func hasPendingWrites() throws -> Bool
    func discardPendingWrites() async throws
    func sync(spreadsheetId: String) async -> Bool
}

@MainActor
@Observable
final class SettingsSheetSwitchStore {
    private(set) var pendingConfirmation: SpreadsheetFile?
    private(set) var errorMessage: String?
    private(set) var isSwitching = false

    private let settings: SettingsStore
    private let sync: any SheetSwitchSyncing
    private let onSynced: () -> Void

    init(settings: SettingsStore, sync: any SheetSwitchSyncing, onSynced: @escaping () -> Void = {}) {
        self.settings = settings
        self.sync = sync
        self.onSynced = onSynced
    }

    func requestSwitch(to spreadsheet: SpreadsheetFile) async -> SettingsSheetSwitchResult {
        errorMessage = nil
        guard !isSwitching else {
            errorMessage = "A sheet switch is already in progress."
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
        guard !isSwitching else {
            errorMessage = "A sheet switch is already in progress."
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

    private func switchNow(to spreadsheet: SpreadsheetFile) async -> Bool {
        guard await sync.sync(spreadsheetId: spreadsheet.spreadsheetId) else {
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
