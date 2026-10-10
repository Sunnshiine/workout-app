import Observation

enum SheetSwitchResult: Equatable {
    case switched
    case requiresConfirmation(SheetSelection)
    case unchanged
    case failed(DestructiveTransitionFailure)
}

enum SignOutResult: Equatable {
    case ready
    case requiresConfirmation
    case failed(DestructiveTransitionFailure)
}

enum SyncNowResult: Equatable {
    case synced
    case noSheet
    case syncInProgress
    case failed
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
    var isSyncing: Bool { get }
    var outcome: SyncOutcome { get }

    func sync(spreadsheetId: String) async -> Bool
    func hasPendingWrites() throws -> Bool
    func discardPendingWrites() async throws
}

@MainActor
@Observable
final class SheetConnection {
    private var isTransitioning = false

    private let settings: SettingsStore
    private let sync: any SheetSwitchSyncing
    private let onSynced: () -> Void
    private static let unsyncedFromPreviousSheetMessage =
        "You have unsynced changes from a previous sheet. Review them in Settings before switching."

    init(settings: SettingsStore, sync: any SheetSwitchSyncing, onSynced: @escaping () -> Void) {
        self.settings = settings
        self.sync = sync
        self.onSynced = onSynced
    }

    var canBeginDestructiveTransition: Bool {
        !isTransitioning && !sync.isSyncing
    }

    var canSyncNow: Bool {
        canBeginDestructiveTransition && settings.spreadsheetId != nil
    }

    var syncNowDetail: String {
        SyncNowDetail.text(
            outcome: sync.outcome,
            isSyncing: sync.isSyncing,
            hasSheet: settings.spreadsheetId != nil
        )
    }

    @discardableResult
    func syncNow() async -> SyncNowResult {
        guard let spreadsheetId = settings.spreadsheetId else { return .noSheet }
        guard canBeginDestructiveTransition else { return .syncInProgress }

        let didSync = await sync.sync(spreadsheetId: spreadsheetId)
        onSynced()
        return didSync ? .synced : .failed
    }

    func requestSwitch(to spreadsheet: SpreadsheetFile) async -> SheetSwitchResult {
        await requestSwitch(to: SheetSelection(spreadsheet))
    }

    func requestSwitch(to selection: SheetSelection) async -> SheetSwitchResult {
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

    func connect(_ selection: SheetSelection) async -> String? {
        switch await requestSwitch(to: selection) {
        case .switched, .unchanged: nil
        case .requiresConfirmation: Self.unsyncedFromPreviousSheetMessage
        case .failed(let failure): failure.message
        }
    }

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

    func requestSignOut() -> SignOutResult {
        guard canBeginDestructiveTransition else { return .failed(.syncInProgress) }

        do {
            return try sync.hasPendingWrites() ? .requiresConfirmation : .ready
        } catch {
            return .failed(.pendingCheckFailed)
        }
    }

    func signOut() async throws(DestructiveTransitionFailure) {
        guard canBeginDestructiveTransition else { throw .syncInProgress }

        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await sync.discardPendingWrites()
        } catch {
            throw .discardFailed
        }
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
