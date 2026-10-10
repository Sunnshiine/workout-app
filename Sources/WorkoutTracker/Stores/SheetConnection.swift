import Observation

enum SettingsSheetSwitchResult: Equatable {
    case switched
    case requiresConfirmation
    case unchanged
    case failed
}

enum SettingsSignOutResult: Equatable {
    case ready
    case requiresConfirmation
    case failed
}

/// Not a `SpreadsheetFile`, because the pasted-URL fallback has no title and must still switch
/// through the same Destructive Transition as the Drive picker.
struct SheetSelection: Equatable {
    let spreadsheetId: String
    let title: String?

    init(spreadsheetId: String, title: String? = nil) {
        self.spreadsheetId = spreadsheetId
        self.title = title
    }

    init(_ file: SpreadsheetFile) {
        self.spreadsheetId = file.spreadsheetId
        self.title = file.name
    }
}

@MainActor
protocol SheetSwitchSyncing: AnyObject {
    /// Any sync or pending-write flush, including those this connection did not start: the flush a
    /// logged Set queues, or the stage's sync on appear.
    var isSyncing: Bool { get }
    var outcome: SyncOutcome { get }

    func sync(spreadsheetId: String) async -> Bool
    func hasPendingWrites() throws -> Bool
    func discardPendingWrites() async throws
}

/// Sync now, switching the configured Sheet, and signing out. Switching and signing out are one
/// Destructive Transition, refused while any sync or flush runs. One instance serves onboarding,
/// Settings, Developer Tools, and the CLI for the app's lifetime, and Settings presents whatever
/// `errorMessage` and `pendingConfirmation` hold.
@MainActor
@Observable
final class SheetConnection {
    private(set) var pendingConfirmation: SheetSelection?
    private(set) var errorMessage: String?
    private(set) var isTransitioning = false

    private let settings: SettingsStore
    private let sync: any SheetSwitchSyncing
    private let onSynced: () -> Void
    private static let syncInProgressMessage = "A sync is already in progress."
    private static let pendingCheckFailedMessage = "Couldn't check pending logs. Try again."
    private static let discardFailedMessage = "Couldn't discard pending logs. Try again."
    private static let unsyncedFromPreviousSheetMessage =
        "You have unsynced changes from a previous sheet. Review them in Settings before switching."

    init(settings: SettingsStore, sync: any SheetSwitchSyncing, onSynced: @escaping () -> Void = {}) {
        self.settings = settings
        self.sync = sync
        self.onSynced = onSynced
    }

    var canBeginDestructiveTransition: Bool {
        !isTransitioning && !sync.isSyncing
    }

    var canSyncNow: Bool {
        sheetToSync != nil
    }

    private var sheetToSync: String? {
        canBeginDestructiveTransition ? settings.spreadsheetId : nil
    }

    var syncNowDetail: String {
        SyncNowDetail.text(
            outcome: sync.outcome,
            isSyncing: sync.isSyncing,
            hasSheet: settings.spreadsheetId != nil
        )
    }

    @discardableResult
    func syncNow() async -> Bool {
        guard let spreadsheetId = sheetToSync else { return false }

        let didSync = await sync.sync(spreadsheetId: spreadsheetId)
        onSynced()
        return didSync
    }

    func requestSwitch(to spreadsheet: SpreadsheetFile) async -> SettingsSheetSwitchResult {
        await requestSwitch(to: SheetSelection(spreadsheet))
    }

    func requestSwitch(to selection: SheetSelection) async -> SettingsSheetSwitchResult {
        errorMessage = nil
        guard canBeginDestructiveTransition else {
            errorMessage = Self.syncInProgressMessage
            return .failed
        }

        if selection.spreadsheetId == settings.spreadsheetId {
            commit(selection)
            return .unchanged
        }

        do {
            guard try !sync.hasPendingWrites() else {
                pendingConfirmation = selection
                return .requiresConfirmation
            }
        } catch {
            errorMessage = Self.pendingCheckFailedMessage
            return .failed
        }

        isTransitioning = true
        defer { isTransitioning = false }
        return await switchNow(to: selection) ? .switched : .failed
    }

    /// Onboarding's selection, returning the message to show when it did not commit. A prior Sheet's
    /// unsynced writes are reported, not offered for discard; that choice lives in Settings.
    func connect(_ selection: SheetSelection) async -> String? {
        defer {
            errorMessage = nil
            pendingConfirmation = nil
        }
        switch await requestSwitch(to: selection) {
        case .switched, .unchanged:
            return nil
        case .failed:
            return errorMessage
        case .requiresConfirmation:
            return Self.unsyncedFromPreviousSheetMessage
        }
    }

    func confirmPendingSwitch() async -> Bool {
        errorMessage = nil
        guard let selection = pendingConfirmation else { return false }
        guard canBeginDestructiveTransition else {
            errorMessage = Self.syncInProgressMessage
            return false
        }

        isTransitioning = true
        defer { isTransitioning = false }

        do {
            try await sync.discardPendingWrites()
        } catch {
            errorMessage = Self.discardFailedMessage
            return false
        }
        pendingConfirmation = nil
        return await switchNow(to: selection)
    }

    func cancelPendingSwitch() {
        pendingConfirmation = nil
    }

    func requestSignOut() -> SettingsSignOutResult {
        errorMessage = nil
        guard canBeginDestructiveTransition else {
            errorMessage = Self.syncInProgressMessage
            return .failed
        }

        do {
            return try sync.hasPendingWrites() ? .requiresConfirmation : .ready
        } catch {
            errorMessage = Self.pendingCheckFailedMessage
            return .failed
        }
    }

    func prepareSignOut() async -> Bool {
        errorMessage = nil
        guard canBeginDestructiveTransition else {
            errorMessage = Self.syncInProgressMessage
            return false
        }

        isTransitioning = true
        defer { isTransitioning = false }

        do {
            try await sync.discardPendingWrites()
        } catch {
            errorMessage = Self.discardFailedMessage
            return false
        }
        return true
    }

    /// Discards the pending writes and clears the selection; the caller ends the Google session.
    func signOut() async -> Bool {
        guard await prepareSignOut() else { return false }
        settings.signOut()
        return true
    }

    func clearError() {
        errorMessage = nil
    }

    private func switchNow(to selection: SheetSelection) async -> Bool {
        guard await sync.sync(spreadsheetId: selection.spreadsheetId) else {
            errorMessage = "Couldn't sync selected sheet. Try again."
            return false
        }
        commit(selection)
        onSynced()
        return true
    }

    private func commit(_ selection: SheetSelection) {
        if let title = selection.title {
            settings.setSpreadsheet(id: selection.spreadsheetId, title: title)
        } else {
            settings.setSpreadsheet(id: selection.spreadsheetId)
        }
    }
}
