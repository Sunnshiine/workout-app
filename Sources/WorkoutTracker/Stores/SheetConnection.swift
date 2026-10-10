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

/// A spreadsheet the athlete has chosen to switch to. Modelled independently of `SpreadsheetFile`
/// so every selection path — the Drive picker (which carries a title) and the pasted-URL fallback
/// (which does not) — can flow through the same safe switch transaction.
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
    /// A sync or a pending-write flush is running right now, whoever started it: the background
    /// flush the athlete's last logged Set queued, or the sync the stage ran on appear.
    var isSyncing: Bool { get }
    var outcome: SyncOutcome { get }

    func sync(spreadsheetId: String) async -> Bool
    func hasPendingWrites() throws -> Bool
    func discardPendingWrites() async throws
}

/// The athlete's connection to the configured Sheet: Sync now, switching Sheets, and signing out.
/// Switching and signing out are one Destructive Transition, and neither may start while a sync runs.
@MainActor
@Observable
final class SheetConnection {
    private(set) var pendingConfirmation: SheetSelection?
    private(set) var errorMessage: String?
    private(set) var isTransitioning = false
    private(set) var isSyncInFlight = false

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
        !isTransitioning && !isSyncInFlight && !sync.isSyncing
    }

    var canSyncNow: Bool {
        settings.spreadsheetId != nil && canBeginDestructiveTransition
    }

    var syncNowDetail: String {
        SyncNowDetail.text(
            outcome: sync.outcome,
            isSyncing: isSyncInFlight || sync.isSyncing,
            hasSheet: settings.spreadsheetId != nil
        )
    }

    @discardableResult
    func syncNow() async -> Bool {
        guard let spreadsheetId = settings.spreadsheetId, !sync.isSyncing else { return false }

        return await runSync {
            let didSync = await sync.sync(spreadsheetId: spreadsheetId)
            onSynced()
            return didSync
        } ?? false
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

    /// Onboarding's selection: the alert message when the selection did not commit, `nil` when it did.
    /// Onboarding starts with no committed sheet, so a prior sheet's unsynced writes are surfaced
    /// rather than offered for discard; that flow lives in Settings.
    func connect(_ selection: SheetSelection) async -> String? {
        switch await requestSwitch(to: selection) {
        case .switched, .unchanged:
            return nil
        case .failed:
            return errorMessage
        case .requiresConfirmation:
            pendingConfirmation = nil
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

    private func runSync<T: Sendable>(_ operation: () async -> T) async -> T? {
        guard !isSyncInFlight else { return nil }

        isSyncInFlight = true
        defer { isSyncInFlight = false }

        return await operation()
    }

    private func switchNow(to selection: SheetSelection) async -> Bool {
        guard
            let didSync = await runSync({
                await sync.sync(spreadsheetId: selection.spreadsheetId)
            })
        else {
            errorMessage = Self.syncInProgressMessage
            return false
        }

        guard didSync else {
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
