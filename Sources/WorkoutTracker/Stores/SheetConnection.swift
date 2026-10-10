import Observation

enum SettingsSheetSwitchResult: Equatable {
    case switched
    case requiresConfirmation(SheetSelection)
    case unchanged
    case failed(DestructiveTransitionFailure)
}

enum SettingsSignOutResult: Equatable {
    case ready
    case requiresConfirmation
    case failed(DestructiveTransitionFailure)
}

enum DestructiveTransitionFailure: Error, Equatable {
    case syncInProgress
    case pendingCheckFailed
    case discardFailed
    case syncFailed

    var message: String {
        switch self {
        case .syncInProgress: "A sync is already in progress."
        case .pendingCheckFailed: "Couldn't check pending logs. Try again."
        case .discardFailed: "Couldn't discard pending logs. Try again."
        case .syncFailed: "Couldn't sync selected sheet. Try again."
        }
    }
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
/// Settings, Developer Tools, and the CLI for the app's lifetime, so it holds no presentation
/// state. Each result carries its reason, and each caller keeps its own alert.
@MainActor
@Observable
final class SheetConnection {
    private var isTransitioning = false

    private let settings: SettingsStore
    private let sync: any SheetSwitchSyncing
    private let onSynced: () -> Void
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
        guard canBeginDestructiveTransition else { return .failed(.syncInProgress) }

        if selection.spreadsheetId == settings.spreadsheetId {
            commit(selection)
            return .unchanged
        }

        do {
            guard try !sync.hasPendingWrites() else { return .requiresConfirmation(selection) }
        } catch {
            return .failed(.pendingCheckFailed)
        }

        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await switchNow(to: selection)
            return .switched
        } catch {
            return .failed(error)
        }
    }

    /// Onboarding's selection, returning the message to show when it did not commit. A prior Sheet's
    /// unsynced writes are reported, not offered for discard; that choice lives in Settings.
    func connect(_ selection: SheetSelection) async -> String? {
        switch await requestSwitch(to: selection) {
        case .switched, .unchanged: nil
        case .requiresConfirmation: Self.unsyncedFromPreviousSheetMessage
        case .failed(let failure): failure.message
        }
    }

    /// Discards the pending writes, then makes the switch `requestSwitch` held for confirmation.
    func confirmSwitch(to selection: SheetSelection) async throws(DestructiveTransitionFailure) {
        guard canBeginDestructiveTransition else { throw .syncInProgress }

        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await sync.discardPendingWrites()
        } catch {
            throw .discardFailed
        }
        try await switchNow(to: selection)
    }

    func requestSignOut() -> SettingsSignOutResult {
        guard canBeginDestructiveTransition else { return .failed(.syncInProgress) }

        do {
            return try sync.hasPendingWrites() ? .requiresConfirmation : .ready
        } catch {
            return .failed(.pendingCheckFailed)
        }
    }

    func prepareSignOut() async throws(DestructiveTransitionFailure) {
        guard canBeginDestructiveTransition else { throw .syncInProgress }

        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await sync.discardPendingWrites()
        } catch {
            throw .discardFailed
        }
    }

    /// Discards the pending writes and clears the selection; the caller ends the Google session.
    func signOut() async throws(DestructiveTransitionFailure) {
        try await prepareSignOut()
        settings.signOut()
    }

    private func switchNow(to selection: SheetSelection) async throws(DestructiveTransitionFailure) {
        guard await sync.sync(spreadsheetId: selection.spreadsheetId) else { throw .syncFailed }
        commit(selection)
        onSynced()
    }

    private func commit(_ selection: SheetSelection) {
        if let title = selection.title {
            settings.setSpreadsheet(id: selection.spreadsheetId, title: title)
        } else {
            settings.setSpreadsheet(id: selection.spreadsheetId)
        }
    }
}
