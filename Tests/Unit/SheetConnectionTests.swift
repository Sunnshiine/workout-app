import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@Test(arguments: [
    (DestructiveTransitionFailure.syncInProgress, "A sync is already in progress."),
    (.pendingCheckFailed, "Couldn't check pending logs. Try again."),
    (.discardFailed, "Couldn't discard pending logs. Try again."),
    (.syncFailed, "Couldn't sync selected sheet. Try again."),
    (.holdsNoBlock, "No training blocks found in this sheet")
])
func everyDestructiveTransitionFailureSaysWhy(failure: DestructiveTransitionFailure, expected: String) {
    #expect(failure.message == expected)
}

@Test(
    arguments: [
        (SheetSwitchResult.switched, nil),
        (.unchanged, nil),
        (
            .requiresConfirmation(SheetSelection(spreadsheetId: "new-sheet")),
            "You have unsynced changes from a previous sheet. Review them in Settings before switching."
        ),
        (.failed(.syncFailed), "Couldn't sync selected sheet. Try again."),
        (.failed(.holdsNoBlock), "No training blocks found in this sheet"),
        (.failed(.syncInProgress), "A sync is already in progress.")
    ] as [(SheetSwitchResult, String?)]
)
func onboardingSaysWhyASelectionDidNotConnect(result: SheetSwitchResult, expected: String?) {
    #expect(result.onboardingMessage == expected)
}

@MainActor
@Test func syncNowSyncsTheConfiguredSheetAndReloadsWorkoutState() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: context)
    var reloadedBlockTabs: [String] = []
    let connection = SheetConnection(settings: settings, sync: sync) {
        reloadedBlockTabs += (try? context.fetch(FetchDescriptor<Block>()).map(\.tabName)) ?? []
    }

    let result = await connection.syncNow()

    #expect(result == .synced)
    #expect(reloadedBlockTabs == ["Block 27"])
    #expect(await client.syncedSpreadsheetIds() == ["current-sheet"])
}

@MainActor
@Test func syncNowReportsASyncThatCouldNotReachTheSheetAsFailed() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid, failOffline: true)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    #expect(await connection.syncNow() == .failed)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func syncNowRejectsARepeatTapWhileItsSyncIsRunning() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: sync) { reloadCount += 1 }

    let firstTap = Task { await connection.syncNow() }
    await client.waitUntilHeld()
    let repeatTap = await connection.syncNow()
    client.release()

    #expect(repeatTap == .syncInProgress)
    #expect(await firstTap.value == .synced)
    #expect(reloadCount == 1)
    #expect(client.tabTitleReads == 1)
}

@MainActor
@Test func sheetSwitchReplacesStaleCachedBlockOnlyAfterSyncingNewSheet() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: context)
    var reloadedOn: [String?] = []
    let connection = SheetConnection(settings: settings, sync: sync) { reloadedOn.append(settings.spreadsheetId) }

    let result = await connection.requestSwitch(
        to: SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)
    )

    #expect(result == .switched)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.spreadsheetTitle == "New Training Log")
    #expect(reloadedOn == ["new-sheet"])
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 27"])
    #expect(await client.syncedSpreadsheetIds() == ["new-sheet"])
}

@MainActor
@Test func titlelessSelectionSwitchSyncsNewSheetThenClearsStaleTitle() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: context)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: sync) { reloadCount += 1 }

    let result = await connection.requestSwitch(to: SheetSelection(spreadsheetId: "new-sheet", title: nil))

    #expect(result == .switched)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.spreadsheetTitle == nil)
    #expect(reloadCount == 1)
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 27"])
    #expect(await client.syncedSpreadsheetIds() == ["new-sheet"])
}

@MainActor
@Test func reselectingTheCurrentSheetRefreshesItsTitleWithoutSyncing() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "same-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }

    let result = await connection.requestSwitch(
        to: SpreadsheetFile(name: "Renamed Training Log", spreadsheetId: "same-sheet", modifiedDate: .distantPast)
    )

    #expect(result == .unchanged)
    #expect(settings.spreadsheetId == "same-sheet")
    #expect(settings.spreadsheetTitle == "Renamed Training Log")
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    #expect(await client.syncedSpreadsheetIds() == [])
    #expect(reloadCount == 0)
}

@MainActor
@Test func oldSheetPendingWritesAreNeverFlushedToNewlySelectedSheet() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    let result = await connection.requestSwitch(to: newSheet)

    #expect(result == .requiresConfirmation(SheetSelection(spreadsheetId: "new-sheet", title: "New Training Log")))
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    #expect(await client.syncedSpreadsheetIds() == [])

    try await connection.confirmSwitch(to: SheetSelection(newSheet))

    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.spreadsheetTitle == "New Training Log")
    #expect(reloadCount == 1)
    #expect(await client.updatedSpreadsheetIds() == [])
    #expect(await client.syncedSpreadsheetIds() == ["new-sheet"])
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 27"])
}

@MainActor
@Test func unreadablePendingWriteCountLeavesTheSheetAloneAndSaysSo() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(pendingWritesError: StubSheetSwitchError.pendingWriteLookupFailed)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: sync) { reloadCount += 1 }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    let result = await connection.requestSwitch(to: newSheet)

    #expect(result == .failed(.pendingCheckFailed))
    #expect(connection.canBeginDestructiveTransition == true)
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(sync.syncedSpreadsheetIds == [])
    #expect(reloadCount == 0)
}

@MainActor
@Test func failedPendingWriteDiscardDoesNotSwitchSheets() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = StubSheetSwitchSync(hasPendingWrites: true, discardError: StubSheetSwitchError.discardFailed)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})
    let newSheet = SheetSelection(spreadsheetId: "new-sheet", title: "New Training Log")

    #expect(await connection.requestSwitch(to: newSheet) == .requiresConfirmation(newSheet))
    await #expect(throws: DestructiveTransitionFailure.discardFailed) {
        try await connection.confirmSwitch(to: newSheet)
    }

    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(sync.syncedSpreadsheetIds == [])
    #expect(connection.canBeginDestructiveTransition == true)
}

@MainActor
@Test func failedSheetSwitchSyncKeepsStaleCacheAndDoesNotCommitSelection() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid, failOffline: true)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }

    let result = await connection.requestSwitch(
        to: SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)
    )

    #expect(result == .failed(.syncFailed))
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(reloadCount == 0)
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 26"])
}

@MainActor
@Test func sheetSwitchToASheetWithNoBlockTabSaysSoAndCommitsNothing() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Notes"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }

    let result = await connection.requestSwitch(to: SheetSelection(spreadsheetId: "new-sheet", title: "Notes Only"))

    #expect(result == .failed(.holdsNoBlock))
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(reloadCount == 0)
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 26"])
}

@MainActor
@Test func failedTitlelessSelectionSwitchKeepsPreviousSelectionAndCache() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid, failOffline: true)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }

    let result = await connection.requestSwitch(to: SheetSelection(spreadsheetId: "new-sheet", title: nil))

    #expect(result == .failed(.syncFailed))
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(reloadCount == 0)
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 26"])
}

@MainActor
@Test func failedConfirmedSheetSwitchSyncDiscardsTheOldLogsButKeepsTheOldSheet() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid, failOffline: true)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }
    let newSheet = SheetSelection(spreadsheetId: "new-sheet", title: "New Training Log")

    #expect(await connection.requestSwitch(to: newSheet) == .requiresConfirmation(newSheet))
    await #expect(throws: DestructiveTransitionFailure.syncFailed) {
        try await connection.confirmSwitch(to: newSheet)
    }

    #expect(settings.spreadsheetId == "old-sheet")
    #expect(settings.spreadsheetTitle == "Old Training Log")
    #expect(reloadCount == 0)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 26"])
}

@MainActor
@Test(.timeLimit(.minutes(1))) func overlappingSheetSwitchIsRejectedWhileFirstSyncIsRunning() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})
    let firstSheet = SpreadsheetFile(name: "First Training Log", spreadsheetId: "first-sheet", modifiedDate: .distantPast)
    let secondSheet = SpreadsheetFile(name: "Second Training Log", spreadsheetId: "second-sheet", modifiedDate: .distantPast)

    let firstTask = Task { await connection.requestSwitch(to: firstSheet) }
    await client.waitUntilHeld()
    let secondResult = await connection.requestSwitch(to: secondSheet)
    client.release()
    let firstResult = await firstTask.value

    #expect(firstResult == .switched)
    #expect(secondResult == .failed(.syncInProgress))
    #expect(settings.spreadsheetId == "first-sheet")
    #expect(settings.spreadsheetTitle == "First Training Log")
    #expect(client.tabTitleReads == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func overlappingConfirmedSheetSwitchIsRejectedWhileDiscardIsRunning() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = SuspendedDiscardSheetSwitchSync()
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})
    let newSheet = SheetSelection(spreadsheetId: "new-sheet", title: "New Training Log")

    let confirmTask = Task { try await connection.confirmSwitch(to: newSheet) }
    await sync.waitForDiscardStart()

    #expect(connection.canBeginDestructiveTransition == false)
    await #expect(throws: DestructiveTransitionFailure.syncInProgress) {
        try await connection.confirmSwitch(to: newSheet)
    }
    sync.completeDiscard()
    try await confirmTask.value

    #expect(sync.discardPendingWriteCallCount == 1)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
}

@MainActor
@Test func signingOutWithNothingQueuedClearsTheSheetAndTheSession() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    #expect(connection.requestSignOut() == .ready)
    try await connection.signOut()

    #expect(settings.spreadsheetId == nil)
    #expect(settings.spreadsheetTitle == nil)
    #expect(settings.isSignedIn == false)
}

@MainActor
@Test func confirmedSignOutDiscardsTheQueuedSetLogsAndClearsTheSheet() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context), onSynced: {})

    #expect(connection.requestSignOut() == .requiresConfirmation)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    try await connection.signOut()

    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(await client.updatedSpreadsheetIds() == [])
    #expect(settings.spreadsheetId == nil)
    #expect(settings.isSignedIn == false)
}

@MainActor
@Test func failedPendingWriteDiscardKeepsTheSheetAndTheSession() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")
    let sync = StubSheetSwitchSync(hasPendingWrites: true, discardError: StubSheetSwitchError.discardFailed)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    #expect(connection.requestSignOut() == .requiresConfirmation)
    await #expect(throws: DestructiveTransitionFailure.discardFailed) {
        try await connection.signOut()
    }

    #expect(settings.spreadsheetId == "current-sheet")
    #expect(settings.spreadsheetTitle == "Current Training Log")
    #expect(settings.isSignedIn == true)
    #expect(connection.canBeginDestructiveTransition == true)
}

@MainActor
@Test func unreadablePendingWriteCountBlocksSignOutAndSaysSo() throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")
    let sync = StubSheetSwitchSync(pendingWritesError: StubSheetSwitchError.pendingWriteLookupFailed)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    #expect(connection.requestSignOut() == .failed(.pendingCheckFailed))
    #expect(settings.spreadsheetId == "current-sheet")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func signOutIsRejectedWhileASheetSwitchDiscardIsRunning() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = SuspendedDiscardSheetSwitchSync()
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let confirmTask = Task { try await connection.confirmSwitch(to: SheetSelection(spreadsheetId: "new-sheet")) }
    await sync.waitForDiscardStart()

    #expect(connection.requestSignOut() == .failed(.syncInProgress))
    await #expect(throws: DestructiveTransitionFailure.syncInProgress) {
        try await connection.signOut()
    }
    sync.completeDiscard()
    try await confirmTask.value

    #expect(sync.discardPendingWriteCallCount == 1)
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.isSignedIn == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func syncNowSignOutAndASecondSwitchAreRejectedWhileASwitchSyncsTheNewSheet() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let sync = SuspendedSyncSheetSwitchSync()
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let switchTask = Task { await connection.requestSwitch(to: SheetSelection(spreadsheetId: "new-sheet")) }
    await sync.waitForSyncStart()

    #expect(connection.canSyncNow == false)
    #expect(await connection.syncNow() == .syncInProgress)
    #expect(connection.requestSignOut() == .failed(.syncInProgress))
    #expect(await connection.requestSwitch(to: SheetSelection(spreadsheetId: "other-sheet")) == .failed(.syncInProgress))
    sync.completeSync()

    #expect(await switchTask.value == .switched)
    #expect(sync.syncedSpreadsheetIds == ["new-sheet"])
    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.isSignedIn == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func syncNowAndASheetSwitchAreRejectedWhileSignOutDiscardsTheQueue() async throws {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")
    let sync = SuspendedDiscardSheetSwitchSync()
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let signOutTask = Task { try await connection.signOut() }
    await sync.waitForDiscardStart()

    #expect(connection.canSyncNow == false)
    #expect(await connection.syncNow() == .syncInProgress)
    #expect(await connection.requestSwitch(to: SheetSelection(spreadsheetId: "other-sheet")) == .failed(.syncInProgress))
    sync.completeDiscard()
    try await signOutTask.value

    #expect(sync.syncedSpreadsheetIds == [])
    #expect(settings.spreadsheetId == nil)
    #expect(settings.isSignedIn == false)
}

@MainActor
@Test func syncNowIsRefusedUntilASheetIsConnected() async {
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    let sync = StubSheetSwitchSync()
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    #expect(connection.canSyncNow == false)
    #expect(connection.syncNowDetail == "Connect a sheet first")
    #expect(await connection.syncNow() == .noSheet)
    #expect(sync.syncedSpreadsheetIds == [])

    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")

    #expect(connection.canSyncNow == true)
    #expect(connection.syncNowDetail == "Refresh workout state")
}

@MainActor
@Test func signOutAndSheetSwitchAreRejectedWhileABackgroundSyncIsRunning() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let backgroundSync = Task { await sync.sync(spreadsheetId: "current-sheet") }
    await client.waitUntilHeld()

    #expect(SyncStatusBannerPresentation(outcome: sync.outcome, isSyncing: sync.isSyncing)?.text == "Syncing")
    #expect(connection.canBeginDestructiveTransition == false)
    #expect(connection.requestSignOut() == .failed(.syncInProgress))
    await #expect(throws: DestructiveTransitionFailure.syncInProgress) { try await connection.signOut() }
    #expect(await connection.requestSwitch(to: SheetSelection(spreadsheetId: "other-sheet")) == .failed(.syncInProgress))
    await #expect(throws: DestructiveTransitionFailure.syncInProgress) {
        try await connection.confirmSwitch(to: SheetSelection(spreadsheetId: "other-sheet"))
    }
    #expect(settings.spreadsheetId == "current-sheet")
    #expect(client.tabTitleReads == 1)

    client.release()

    #expect(await backgroundSync.value == true)
    #expect(connection.canBeginDestructiveTransition == true)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aFlushThatOverlapsASyncLeavesTheDestructiveTransitionGuardClosed() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")

    let client = HeldSheetsClient(
        titles: ["Intro", "Block 27"],
        grid: WorkoutFixtureScenarios.replacementSheetGrid,
        holdsTabSnapshot: true
    )
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let backgroundSync = Task { await sync.sync(spreadsheetId: "current-sheet") }

    await client.waitUntilHeld()
    #expect(sync.isSyncing == true)
    #expect(connection.canBeginDestructiveTransition == false)

    await sync.flushPending(spreadsheetId: "current-sheet")

    #expect(SyncStatusBannerPresentation(outcome: sync.outcome, isSyncing: sync.isSyncing)?.text == "Syncing")
    #expect(sync.isSyncing == true)
    #expect(connection.canBeginDestructiveTransition == false)
    #expect(connection.requestSignOut() == .failed(.syncInProgress))

    client.release()
    await client.waitUntilHeld()
    #expect(sync.isSyncing == true)
    #expect(connection.canBeginDestructiveTransition == false)

    client.release()

    #expect(await backgroundSync.value == true)
    #expect(sync.isSyncing == false)
    #expect(connection.canBeginDestructiveTransition == true)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aFlushWithNoSyncAroundItAlsoClosesTheDestructiveTransitionGuard() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    try queueReplacementSquatLog(in: container.mainContext)

    let client = HeldSheetsClient(
        titles: ["Intro", "Block 27"],
        grid: WorkoutFixtureScenarios.replacementSheetGrid,
        holdsTabSnapshot: true
    )
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let flush = Task { await sync.flushPending(spreadsheetId: "current-sheet") }

    await client.waitUntilHeld()
    #expect(sync.isSyncing == true)
    #expect(connection.canBeginDestructiveTransition == false)

    client.release()
    await flush.value

    #expect(sync.isSyncing == false)
    #expect(connection.canBeginDestructiveTransition == true)
}

@MainActor
@Test func syncNowIsRejectedWhileABackgroundSyncIsRunning() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")

    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: sync) { reloadCount += 1 }

    let backgroundSync = Task { await sync.sync(spreadsheetId: "current-sheet") }
    await client.waitUntilHeld()

    #expect(await connection.syncNow() == .syncInProgress)
    #expect(reloadCount == 0)
    #expect(client.tabTitleReads == 1)

    client.release()

    #expect(await backgroundSync.value == true)
    #expect(await connection.syncNow() == .synced)
    #expect(reloadCount == 1)
    #expect(client.tabTitleReads == 2)
}

// MARK: - Onboarding

@MainActor
@Test func confirmedSheetSwitchToASheetWithNoBlockTabSaysSoAndKeepsTheOldSheet() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try seedStaleBlock(tabName: "Block 26", into: context)
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Notes"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context), onSynced: {})
    let newSheet = SheetSelection(spreadsheetId: "new-sheet", title: "Notes Only")

    #expect(await connection.requestSwitch(to: newSheet) == .requiresConfirmation(newSheet))
    await #expect(throws: DestructiveTransitionFailure.holdsNoBlock) {
        try await connection.confirmSwitch(to: newSheet)
    }

    #expect(settings.spreadsheetId == "old-sheet")
    #expect(try context.fetch(FetchDescriptor<Block>()).map(\.tabName) == ["Block 26"])
}

@MainActor
@Test func onboardingSelectionWithAPreviousSheetsPendingLogsAsksForConfirmationAndKeepsThem() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context), onSynced: {})

    let result = await connection.requestSwitch(to: SheetSelection(spreadsheetId: "new-sheet"))

    #expect(result == .requiresConfirmation(SheetSelection(spreadsheetId: "new-sheet")))
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    #expect(await client.syncedSpreadsheetIds() == [])
}

@MainActor
@Test func onboardingSelectionThatFailsToSyncReturnsTheReason() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid, failOffline: true)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let result = await connection.requestSwitch(to: SheetSelection(spreadsheetId: "new-sheet"))

    #expect(result == .failed(.syncFailed))
    #expect(result.onboardingMessage == "Couldn't sync selected sheet. Try again.")
    #expect(settings.spreadsheetId == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func anOnboardingSelectionRefusedMidSyncReturnsTheRefusalAndThePickedSheetCommits() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let picked = Task { await connection.requestSwitch(to: SheetSelection(spreadsheetId: "picked-sheet", title: "Picked")) }
    await client.waitUntilHeld()
    let pasted = await connection.requestSwitch(to: SheetSelection(spreadsheetId: "pasted-sheet"))
    client.release()

    #expect(pasted == .failed(.syncInProgress))
    #expect(await picked.value == .switched)
    #expect(settings.spreadsheetId == "picked-sheet")
    #expect(settings.spreadsheetTitle == "Picked")
    #expect(connection.canBeginDestructiveTransition == true)
}

@MainActor
private func makeCacheSafetyContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "sheet-switch-cache-safety-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
private func seedStaleBlock(tabName: String, into context: ModelContext) throws {
    let block = BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: tabName,
            weeks: [
                ParsedWeek(
                    number: 1,
                    days: [
                        ParsedSession(
                            dayNumber: 1,
                            date: nil,
                            exercises: [
                                ParsedExercise(
                                    name: "Squat",
                                    coachNote: nil,
                                    sets: [
                                        ParsedSet(
                                            index: 0,
                                            prescribedReps: "5",
                                            prescribedLoad: "RPE8",
                                            percentOneRM: nil,
                                            state: .pending,
                                            setLog: nil
                                        )
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    )
    context.insert(block)
    try context.save()
}

@MainActor
private func queueReplacementSquatLog(
    in context: ModelContext,
    dayNumbering: DayNumbering = .headerNumber
) throws {
    context.insert(
        PendingWrite(
            session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
            dayNumbering: dayNumbering,
            exerciseName: "Replacement Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        )
    )
    try context.save()
}

private final class RecordingSheetsClient: SheetsClient, @unchecked Sendable {
    private let titles: [String]
    private let grid: SheetGrid
    private let failOffline: Bool
    private let recorder = CallRecorder()

    init(titles: [String], grid: SheetGrid, failOffline: Bool = false) {
        self.titles = titles
        self.grid = grid
        self.failOffline = failOffline
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if failOffline { throw URLError(.notConnectedToInternet) }
        await recorder.recordSync(spreadsheetId)
        return titles
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        SpreadsheetListPage(spreadsheets: [], nextPageToken: nil)
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
        await recorder.recordUpdate(spreadsheetId)
    }

    func syncedSpreadsheetIds() async -> [String] { await recorder.syncedIds }
    func updatedSpreadsheetIds() async -> [String] { await recorder.updatedIds }
}

private actor CallRecorder {
    private(set) var syncedIds: [String] = []
    private(set) var updatedIds: [String] = []

    func recordSync(_ id: String) { syncedIds.append(id) }
    func recordUpdate(_ id: String) { updatedIds.append(id) }
}

@MainActor
private final class StubSheetSwitchSync: SheetSwitchSyncing {
    let isSyncing = false
    let outcome = SyncOutcome.clear
    private let hasPendingWritesValue: Bool
    private let pendingWritesError: Error?
    private let discardError: Error?
    private(set) var syncedSpreadsheetIds: [String] = []

    init(hasPendingWrites: Bool = false, pendingWritesError: Error? = nil, discardError: Error? = nil) {
        self.hasPendingWritesValue = hasPendingWrites
        self.pendingWritesError = pendingWritesError
        self.discardError = discardError
    }

    func hasPendingWrites() throws -> Bool {
        if let pendingWritesError {
            throw pendingWritesError
        }
        return hasPendingWritesValue
    }

    func discardPendingWrites() async throws {
        if let discardError {
            throw discardError
        }
    }

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        return true
    }
}

private enum StubSheetSwitchError: Error {
    case discardFailed
    case pendingWriteLookupFailed
}

@MainActor
private final class SuspendedDiscardSheetSwitchSync: SheetSwitchSyncing {
    let isSyncing = false
    let outcome = SyncOutcome.clear
    private let heldDiscard = HeldCall()
    private(set) var discardPendingWriteCallCount = 0
    private(set) var syncedSpreadsheetIds: [String] = []

    func hasPendingWrites() throws -> Bool {
        true
    }

    func discardPendingWrites() async throws {
        discardPendingWriteCallCount += 1
        guard !heldDiscard.isHeld else {
            throw StubSheetSwitchError.discardFailed
        }

        await heldDiscard.hold()
    }

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        return true
    }

    func waitForDiscardStart() async {
        await heldDiscard.waitUntilHeld(orRecord: "the sheet switch never started discarding its pending writes")
    }

    func completeDiscard() {
        heldDiscard.release()
    }
}

@MainActor
private final class SuspendedSyncSheetSwitchSync: SheetSwitchSyncing {
    let isSyncing = false
    let outcome = SyncOutcome.clear
    private let heldSync = HeldCall()
    private(set) var syncedSpreadsheetIds: [String] = []

    func hasPendingWrites() throws -> Bool {
        false
    }

    func discardPendingWrites() async throws {}

    func sync(spreadsheetId: String) async -> Bool {
        syncedSpreadsheetIds.append(spreadsheetId)
        await heldSync.hold()
        return true
    }

    func waitForSyncStart() async {
        await heldSync.waitUntilHeld(orRecord: "the sheet switch never started syncing the new sheet")
    }

    func completeSync() {
        heldSync.release()
    }
}
