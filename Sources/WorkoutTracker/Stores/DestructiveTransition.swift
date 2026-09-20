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
protocol SheetSwitchSyncing: ConfiguredSheetSyncing {
    func hasPendingWrites() throws -> Bool
    func discardPendingWrites() async throws
}

@MainActor
@Observable
final class SettingsSheetSwitchStore {
    private(set) var pendingConfirmation: SheetSelection?
    private(set) var errorMessage: String?
    private(set) var isTransitioning = false

    private let settings: SettingsStore
    private let sync: any SheetSwitchSyncing
    private let syncActivity: SettingsSyncActivity
    private let onSynced: () -> Void
    private static let syncInProgressMessage = "A sync is already in progress."
    private static let pendingCheckFailedMessage = "Couldn't check pending logs. Try again."
    private static let discardFailedMessage = "Couldn't discard pending logs. Try again."

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

    /// Switching the configured Sheet and signing out are one domain move. Both abandon Set Logs
    /// the athlete recorded locally that have not yet reached the Sheet (ADR-0001).
    var canBeginDestructiveTransition: Bool {
        !isTransitioning && !syncActivity.isSyncInFlight && !sync.isSyncing
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

    func clearError() {
        errorMessage = nil
    }

    private func switchNow(to selection: SheetSelection) async -> Bool {
        guard
            let didSync = await syncActivity.run({
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
