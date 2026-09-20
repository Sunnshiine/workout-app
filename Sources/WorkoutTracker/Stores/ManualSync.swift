import Observation

@MainActor
protocol ConfiguredSheetSyncing: AnyObject {
    /// A sync or a pending-write flush is running right now, whoever started it.
    /// `SettingsSyncActivity` only sees the work a Settings store started, so this is the other
    /// half: the background flush the athlete's last logged Set queued, or the sync the stage ran
    /// on appear.
    var isSyncing: Bool { get }

    func sync(spreadsheetId: String) async -> Bool
}

@MainActor
@Observable
final class SettingsSyncActivity {
    private(set) var isSyncInFlight = false

    func run<T: Sendable>(_ operation: () async -> T) async -> T? {
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
        guard let spreadsheetId = settings.spreadsheetId, !sync.isSyncing else { return false }

        return await syncActivity.run {
            let didSync = await sync.sync(spreadsheetId: spreadsheetId)
            onSynced()
            return didSync
        } ?? false
    }
}
