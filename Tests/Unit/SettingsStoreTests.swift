import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func isConfiguredRequiresSpreadsheetIdAndAuth() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)
    store.isSignedIn = true
    #expect(store.isConfigured == false)  // no URL yet
    store.setSheetURL("https://docs.google.com/spreadsheets/d/SHEET123/edit")
    #expect(store.spreadsheetId == "SHEET123")
    #expect(store.isConfigured == true)
}

@MainActor
@Test func selectedSpreadsheetPersistsIdAndTitle() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)

    store.setSpreadsheet(id: "SHEET123", title: "Training Log")

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.spreadsheetId == "SHEET123")
    #expect(reloaded.spreadsheetTitle == "Training Log")
}

@MainActor
@Test func newInstallSeedsSystemAppearance() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)

    #expect(store.appearance == .system)
    #expect(defaults.string(forKey: "appearance") == AppearancePreference.system.rawValue)
}

@MainActor
@Test func existingInstallWithoutAppearanceSeedsDark() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    defaults.set("SHEET123", forKey: "spreadsheetId")

    let store = SettingsStore(defaults: defaults)

    #expect(store.appearance == .dark)
    #expect(defaults.string(forKey: "appearance") == AppearancePreference.dark.rawValue)
}

@MainActor
@Test func cachedInstallWithoutAppearanceSeedsDark() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))

    let store = SettingsStore(defaults: defaults, hasPriorAppState: true)

    #expect(store.appearance == .dark)
    #expect(defaults.string(forKey: "appearance") == AppearancePreference.dark.rawValue)
}

@MainActor
@Test func invalidAppearanceFallsBackToDark() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    defaults.set("legacy", forKey: "appearance")

    let store = SettingsStore(defaults: defaults)

    #expect(store.appearance == .dark)
    #expect(defaults.string(forKey: "appearance") == AppearancePreference.dark.rawValue)
}

@MainActor
@Test func appearancePersistsManualChoicesAndDoesNotReseed() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)

    store.setAppearance(.light)
    #expect(SettingsStore(defaults: defaults).appearance == .light)

    store.setAppearance(.dark)
    #expect(SettingsStore(defaults: defaults).appearance == .dark)

    store.setAppearance(.system)
    defaults.set("SHEET123", forKey: "spreadsheetId")
    #expect(SettingsStore(defaults: defaults).appearance == .system)
}

@MainActor
@Test func standardRestDurationPersistsRoundTrip() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)

    #expect(store.standardRestDuration == .standard)

    store.setStandardRestDuration(RestDurationSetting(seconds: 210))

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.standardRestDuration == RestDurationSetting(seconds: 210))
}

@MainActor
@Test func supersetRestDurationPersistsRoundTrip() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)

    #expect(store.supersetRestDuration == .superset)

    store.setSupersetRestDuration(RestDurationSetting(seconds: 90))

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.supersetRestDuration == RestDurationSetting(seconds: 90))
}

#if DEBUG
    @Test func uiTestAppearanceLaunchArgumentParsesSupportedAppearances() {
        #expect(
            UITestFixture.appearanceOverride(
                from: ["WorkoutTracker", "-UITEST_APPEARANCE", "light"]
            ) == .light
        )
        #expect(
            UITestFixture.appearanceOverride(
                from: ["WorkoutTracker", "-UITEST_APPEARANCE", "dark"]
            ) == .dark
        )
        #expect(
            UITestFixture.appearanceOverride(
                from: ["WorkoutTracker", "-UITEST_APPEARANCE", "system"]
            ) == .system
        )
    }

    @Test func uiTestAppearanceLaunchArgumentIgnoresMissingOrUnsupportedAppearances() {
        #expect(UITestFixture.appearanceOverride(from: ["WorkoutTracker"]) == nil)
        #expect(UITestFixture.appearanceOverride(from: ["WorkoutTracker", "-UITEST_APPEARANCE"]) == nil)
        #expect(
            UITestFixture.appearanceOverride(
                from: ["WorkoutTracker", "-UITEST_APPEARANCE", "black"]
            ) == nil
        )
    }
#endif

@MainActor
@Test func signOutClearsAuthAndSpreadsheetSelection() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)
    store.isSignedIn = true
    store.setSpreadsheet(id: "SHEET123", title: "Training Log")

    store.signOut()

    #expect(store.isSignedIn == false)
    #expect(store.spreadsheetId == nil)
    #expect(store.spreadsheetTitle == nil)

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.spreadsheetId == nil)
    #expect(reloaded.spreadsheetTitle == nil)
}

@MainActor
@Test func settingsManualSyncUsesConfiguredSheetAndReloadsWorkoutState() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let sync = StubConfiguredSheetSync()
    var reloadCount = 0
    let store = SettingsManualSyncStore(settings: settings, sync: sync) {
        reloadCount += 1
    }

    let didSync = await store.syncNow()

    #expect(didSync == true)
    #expect(sync.syncedSpreadsheetIds == ["current-sheet"])
    #expect(reloadCount == 1)
    #expect(store.isSyncInFlight == false)
}

@MainActor
@Test func settingsManualSyncRejectsRepeatTapWhileSyncIsRunning() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let sync = SuspendedConfiguredSheetSync()
    var reloadCount = 0
    let store = SettingsManualSyncStore(settings: settings, sync: sync) {
        reloadCount += 1
    }

    let firstSync = Task { await store.syncNow() }
    await sync.waitForSyncStart()

    #expect(store.isSyncInFlight == true)

    let repeatTapResult = await store.syncNow()
    sync.completeSync()
    let firstSyncResult = await firstSync.value

    #expect(firstSyncResult == true)
    #expect(repeatTapResult == false)
    #expect(sync.syncedSpreadsheetIds == ["current-sheet"])
    #expect(reloadCount == 1)
    #expect(store.isSyncInFlight == false)
}

@MainActor
@Test func sheetSwitchIsRejectedWhileSettingsManualSyncIsRunning() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let syncActivity = SettingsSyncActivity()
    let manualSync = SuspendedConfiguredSheetSync()
    let manualStore = SettingsManualSyncStore(
        settings: settings,
        sync: manualSync,
        syncActivity: syncActivity
    )
    let switchSync = StubSheetSwitchSync()
    let switchStore = SettingsSheetSwitchStore(
        settings: settings,
        sync: switchSync,
        syncActivity: syncActivity
    )
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    let manualTask = Task { await manualStore.syncNow() }
    await manualSync.waitForSyncStart()

    let switchResult = await switchStore.requestSwitch(to: newSheet)
    manualSync.completeSync()
    _ = await manualTask.value

    #expect(switchResult == .failed)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(switchSync.syncedSpreadsheetIds.isEmpty)
    #expect(switchStore.errorMessage != nil)
}

@MainActor
@Test func sheetSwitchWithoutPendingWritesCommitsAndSyncsNewSheet() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync()
    var reloadCount = 0
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync) {
        reloadCount += 1
    }

    let result = await store.requestSwitch(
        to: SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)
    )

    #expect(result == .switched)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.spreadsheetTitle == "New Training Log")
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
    #expect(sync.discardPendingWriteCallCount == 0)
    #expect(reloadCount == 1)
}

@MainActor
@Test func sheetSwitchWithPendingWritesWaitsForConfirmation() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(hasPendingWrites: true)
    var reloadCount = 0
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync) {
        reloadCount += 1
    }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    let result = await store.requestSwitch(to: newSheet)

    #expect(result == .requiresConfirmation)
    #expect(store.pendingConfirmation == newSheet)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(sync.syncedSpreadsheetIds.isEmpty)
    #expect(sync.discardPendingWriteCallCount == 0)

    store.cancelPendingSwitch()

    #expect(store.pendingConfirmation == nil)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(sync.syncedSpreadsheetIds.isEmpty)
    #expect(reloadCount == 0)
}

@MainActor
@Test func confirmingSheetSwitchDiscardsPendingWritesThenSyncsNewSheet() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(hasPendingWrites: true)
    var reloadCount = 0
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync) {
        reloadCount += 1
    }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    _ = await store.requestSwitch(to: newSheet)
    let confirmed = await store.confirmPendingSwitch()

    #expect(confirmed == true)
    #expect(store.pendingConfirmation == nil)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.spreadsheetTitle == "New Training Log")
    #expect(sync.hasPendingWritesValue == false)
    #expect(sync.discardPendingWriteCallCount == 1)
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
    #expect(reloadCount == 1)
}

@MainActor
@Test func failedPendingWriteDiscardDoesNotSwitchSheets() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(hasPendingWrites: true, discardError: StubSheetSwitchError.discardFailed)
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync)
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    _ = await store.requestSwitch(to: newSheet)
    let confirmed = await store.confirmPendingSwitch()

    #expect(confirmed == false)
    #expect(store.pendingConfirmation == newSheet)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(sync.hasPendingWritesValue == true)
    #expect(sync.syncedSpreadsheetIds.isEmpty)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func failedSheetSwitchSyncDoesNotCommitOrReload() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(syncSucceeds: false)
    var reloadCount = 0
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync) {
        reloadCount += 1
    }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    let result = await store.requestSwitch(to: newSheet)

    #expect(result == .failed)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
    #expect(reloadCount == 0)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func failedConfirmedSheetSwitchSyncDoesNotCommitOrReload() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(hasPendingWrites: true, syncSucceeds: false)
    var reloadCount = 0
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync) {
        reloadCount += 1
    }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    _ = await store.requestSwitch(to: newSheet)
    let confirmed = await store.confirmPendingSwitch()

    #expect(confirmed == false)
    #expect(store.pendingConfirmation == nil)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(sync.discardPendingWriteCallCount == 1)
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
    #expect(reloadCount == 0)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func overlappingSheetSwitchIsRejectedWhileFirstSyncIsRunning() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = SuspendedSheetSwitchSync()
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync)
    let firstSheet = SpreadsheetFile(name: "First Training Log", spreadsheetId: "first-sheet", modifiedDate: .distantPast)
    let secondSheet = SpreadsheetFile(name: "Second Training Log", spreadsheetId: "second-sheet", modifiedDate: .distantPast)

    let firstTask = Task { await store.requestSwitch(to: firstSheet) }
    await sync.waitForSyncStart()

    let secondResult = await store.requestSwitch(to: secondSheet)
    sync.completeSync()
    let firstResult = await firstTask.value

    #expect(firstResult == .switched)
    #expect(secondResult == .failed)
    #expect(settings.spreadsheetId == "first-sheet")
    #expect(settings.spreadsheetTitle == "First Training Log")
    #expect(sync.syncedSpreadsheetIds == ["first-sheet"])
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func overlappingConfirmedSheetSwitchIsRejectedWhileDiscardIsRunning() async throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let settings = SettingsStore(defaults: defaults)
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = SuspendedDiscardSheetSwitchSync()
    let store = SettingsSheetSwitchStore(settings: settings, sync: sync)
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    _ = await store.requestSwitch(to: newSheet)

    let confirmTask = Task { await store.confirmPendingSwitch() }
    await sync.waitForDiscardStart()

    #expect(store.isSwitching == true)

    let overlappingConfirm = await store.confirmPendingSwitch()
    sync.completeDiscard()
    let confirmed = await confirmTask.value

    #expect(overlappingConfirm == false)
    #expect(confirmed == true)
    #expect(sync.discardPendingWriteCallCount == 1)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
}

@MainActor
private final class StubSheetSwitchSync: SheetSwitchSyncing {
    var hasPendingWritesValue: Bool
    private let discardError: Error?
    private let syncSucceeds: Bool
    private(set) var discardPendingWriteCallCount = 0
    private(set) var syncedSpreadsheetIds: [String] = []

    init(hasPendingWrites: Bool = false, discardError: Error? = nil, syncSucceeds: Bool = true) {
        self.hasPendingWritesValue = hasPendingWrites
        self.discardError = discardError
        self.syncSucceeds = syncSucceeds
    }

    func hasPendingWrites() throws -> Bool {
        hasPendingWritesValue
    }

    func discardPendingWrites() async throws {
        if let discardError {
            throw discardError
        }
        hasPendingWritesValue = false
        discardPendingWriteCallCount += 1
    }

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        return syncSucceeds
    }
}

private enum StubSheetSwitchError: Error {
    case discardFailed
}

@MainActor
private final class StubConfiguredSheetSync: ConfiguredSheetSyncing {
    private let syncSucceeds: Bool
    private(set) var syncedSpreadsheetIds: [String] = []

    init(syncSucceeds: Bool = true) {
        self.syncSucceeds = syncSucceeds
    }

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        return syncSucceeds
    }
}

@MainActor
private final class SuspendedConfiguredSheetSync: ConfiguredSheetSyncing {
    private var syncContinuation: CheckedContinuation<Void, Never>?
    private(set) var syncedSpreadsheetIds: [String] = []

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        await withCheckedContinuation { continuation in
            syncContinuation = continuation
        }
        return true
    }

    func waitForSyncStart() async {
        while syncContinuation == nil {
            await Task.yield()
        }
    }

    func completeSync() {
        syncContinuation?.resume()
        syncContinuation = nil
    }
}

@MainActor
private final class SuspendedDiscardSheetSwitchSync: SheetSwitchSyncing {
    private var discardContinuation: CheckedContinuation<Void, Never>?
    private(set) var discardPendingWriteCallCount = 0
    private(set) var syncedSpreadsheetIds: [String] = []

    func hasPendingWrites() throws -> Bool {
        true
    }

    func discardPendingWrites() async throws {
        discardPendingWriteCallCount += 1
        guard discardContinuation == nil else {
            throw StubSheetSwitchError.discardFailed
        }

        await withCheckedContinuation { continuation in
            discardContinuation = continuation
        }
    }

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        return true
    }

    func waitForDiscardStart() async {
        while discardContinuation == nil {
            await Task.yield()
        }
    }

    func completeDiscard() {
        discardContinuation?.resume()
        discardContinuation = nil
    }
}

@MainActor
private final class SuspendedSheetSwitchSync: SheetSwitchSyncing {
    private var syncContinuation: CheckedContinuation<Void, Never>?
    private(set) var syncedSpreadsheetIds: [String] = []

    func hasPendingWrites() throws -> Bool {
        false
    }

    func discardPendingWrites() async throws {}

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        await withCheckedContinuation { continuation in
            syncContinuation = continuation
        }
        return true
    }

    func waitForSyncStart() async {
        while syncContinuation == nil {
            await Task.yield()
        }
    }

    func completeSync() {
        syncContinuation?.resume()
        syncContinuation = nil
    }
}
