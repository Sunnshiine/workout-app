import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@Test(arguments: [
    (DestructiveTransitionFailure.syncInProgress, "A sync is already in progress."),
    (.pendingCheckFailed, "Couldn't check pending logs. Try again."),
    (.discardFailed, "Couldn't discard pending logs. Try again."),
    (.syncFailed, "Couldn't sync selected sheet. Try again.")
])
func everyDestructiveTransitionFailureSaysWhy(failure: DestructiveTransitionFailure, expected: String) {
    #expect(failure.message == expected)
}

// MARK: - Sync now

@MainActor
@Test func syncNowSyncsTheConfiguredSheetAndReloadsWorkoutState() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    let sync = SyncCoordinator(client: client, context: context)
    var reloadedBlockTabs: [String] = []
    let connection = SheetConnection(settings: settings, sync: sync) {
        reloadedBlockTabs += (try? context.fetch(FetchDescriptor<Block>()).map(\.tabName)) ?? []
    }

    let didSync = await connection.syncNow()

    #expect(didSync == true)
    #expect(reloadedBlockTabs == ["Block 27"])
    #expect(await client.syncedSpreadsheetIds() == ["current-sheet"])
}

@MainActor
@Test(.timeLimit(.minutes(1))) func syncNowRejectsARepeatTapWhileItsSyncIsRunning() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: sync) { reloadCount += 1 }

    let firstTap = Task { await connection.syncNow() }
    await client.waitUntilHeld()
    let repeatTap = await connection.syncNow()
    client.release()

    #expect(repeatTap == false)
    #expect(await firstTap.value == true)
    #expect(reloadCount == 1)
    #expect(client.tabTitleReads == 1)
}

// MARK: - Sheet switch

@MainActor
@Test func sheetSwitchReplacesStaleCachedBlockOnlyAfterSyncingNewSheet() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
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

// The onboarding pasted-URL fallback commits a titleless `SheetSelection`, so the safe transaction
// must sync the new sheet first, then commit the id while clearing any stale title left behind.
@MainActor
@Test func titlelessSelectionSwitchSyncsNewSheetThenClearsStaleTitle() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
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
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
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
    seedStaleBlock(tabName: "Block 26", into: context)
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context)) {
        reloadCount += 1
    }
    let newSheet = SpreadsheetFile(name: "New Training Log", spreadsheetId: "new-sheet", modifiedDate: .distantPast)

    let result = await connection.requestSwitch(to: newSheet)

    // A pending write for the old sheet forces confirmation before anything is synced.
    #expect(result == .requiresConfirmation(SheetSelection(spreadsheetId: "new-sheet", title: "New Training Log")))
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    #expect(await client.syncedSpreadsheetIds() == [])

    try await connection.confirmSwitch(to: SheetSelection(newSheet))

    #expect(settings.spreadsheetId == "new-sheet")
    #expect(settings.spreadsheetTitle == "New Training Log")
    #expect(reloadCount == 1)
    // The old pending write was discarded before the new sheet synced, so it can never be written
    // into the newly selected spreadsheet.
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
    seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid(), failOffline: true)
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

// A failed titleless selection switch (pasted URL that can't sync) must leave onboarding's previous
// selection and cache untouched, exactly like the Drive-picker path.
@MainActor
@Test func failedTitlelessSelectionSwitchKeepsPreviousSelectionAndCache() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    seedStaleBlock(tabName: "Block 26", into: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid(), failOffline: true)
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
    seedStaleBlock(tabName: "Block 26", into: context)
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid(), failOffline: true)
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
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
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

// MARK: - Sign out

@MainActor
@Test func signingOutWithNothingQueuedClearsTheSheetAndTheSession() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.isSignedIn = true
    settings.setSpreadsheet(id: "current-sheet", title: "Current Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
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
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context), onSynced: {})

    #expect(connection.requestSignOut() == .requiresConfirmation)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    try await connection.signOut()

    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(await client.updatedSpreadsheetIds() == [])
    #expect(settings.spreadsheetId == nil)
    #expect(settings.isSignedIn == false)
}

/// Set Logs a failed discard leaves queued still belong on the Sheet (ADR-0001), so the sign-out
/// keeps the Sheet they flush to.
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

// MARK: - The guard against any running sync

/// A sync nobody in Settings started — the stage's sync on appear, or the flush the athlete's last
/// logged Set queued — is still the `SyncCoordinator` talking to the Sheet, and abandoning pending
/// logs underneath it is what `canBeginDestructiveTransition` exists to refuse.
@MainActor
@Test func signOutAndSheetSwitchAreRejectedWhileABackgroundSyncIsRunning() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
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
    // Nothing reached the coordinator: no discard, and no second sync against the other sheet.
    #expect(client.tabTitleReads == 1)

    client.release()

    #expect(await backgroundSync.value == true)
    #expect(connection.canBeginDestructiveTransition == true)
}

/// The overlap is reachable in the app. `SessionPendingWriteSyncAdapter.requestPendingWriteFlush()`
/// fires a flush after every logged Set and `workout flush` makes the same call, so an athlete
/// logging during the stage's sync on appear reaches it. This calls `flushPending` directly, so the
/// interleaving is deterministic rather than a race on an unowned Task (#585).
@MainActor
@Test(.timeLimit(.minutes(1)))
func aFlushThatOverlapsASyncLeavesTheDestructiveTransitionGuardClosed() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")

    let client = HeldSheetsClient(
        titles: ["Intro", "Block 27"],
        grid: replacementSquatGrid(),
        holdsTabSnapshot: true
    )
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let backgroundSync = Task { await sync.sync(spreadsheetId: "current-sheet") }

    await client.waitUntilHeld()
    #expect(sync.isSyncing == true)
    #expect(connection.canBeginDestructiveTransition == false)

    await sync.flushPending(spreadsheetId: "current-sheet")

    // The banner half of the same guard. The banner reads the in-flight count, not the last verdict.
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

/// Guards the flush half of `isSyncing`, so a fix aimed at the sync half cannot narrow it.
@MainActor
@Test(.timeLimit(.minutes(1)))
func aFlushWithNoSyncAroundItAlsoClosesTheDestructiveTransitionGuard() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "current-sheet", title: "Training Log")
    try queueReplacementSquatLog(in: container.mainContext)

    let client = HeldSheetsClient(
        titles: ["Intro", "Block 27"],
        grid: replacementSquatGrid(),
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

    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    var reloadCount = 0
    let connection = SheetConnection(settings: settings, sync: sync) { reloadCount += 1 }

    let backgroundSync = Task { await sync.sync(spreadsheetId: "current-sheet") }
    await client.waitUntilHeld()

    #expect(await connection.syncNow() == false)
    #expect(reloadCount == 0)
    // The Sync now tap stopped at the guard instead of starting a second sync against the same sheet.
    #expect(client.tabTitleReads == 1)

    client.release()

    #expect(await backgroundSync.value == true)
    #expect(await connection.syncNow() == true)
    #expect(reloadCount == 1)
    #expect(client.tabTitleReads == 2)
}

// MARK: - Onboarding

@MainActor
@Test func onboardingSelectionWithAPreviousSheetsPendingLogsSaysSoAndKeepsThem() async throws {
    let container = try makeCacheSafetyContainer()
    let context = container.mainContext
    try queueReplacementSquatLog(in: context)
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    settings.setSpreadsheet(id: "old-sheet", title: "Old Training Log")
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    let connection = SheetConnection(settings: settings, sync: SyncCoordinator(client: client, context: context), onSynced: {})

    let message = await connection.connect(SheetSelection(spreadsheetId: "new-sheet"))

    #expect(message == "You have unsynced changes from a previous sheet. Review them in Settings before switching.")
    #expect(settings.spreadsheetId == "old-sheet")
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    #expect(await client.syncedSpreadsheetIds() == [])
}

@MainActor
@Test func onboardingSelectionThatFailsToSyncReturnsTheReason() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    let client = RecordingSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid(), failOffline: true)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    #expect(await connection.connect(SheetSelection(spreadsheetId: "new-sheet")) == "Couldn't sync selected sheet. Try again.")
    #expect(settings.spreadsheetId == nil)
}

/// Onboarding's "Paste a URL instead" stays live while a picked Sheet syncs, so a pasted URL can
/// be refused mid-sync. The refusal is onboarding's to show; the picked Sheet still commits, and
/// the connection is free for the next transition.
@MainActor
@Test(.timeLimit(.minutes(1))) func anOnboardingSelectionRefusedMidSyncReturnsTheRefusalAndThePickedSheetCommits() async throws {
    let container = try makeCacheSafetyContainer()
    let settings = SettingsStore(defaults: AppDefaults.inMemory())
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: replacementSquatGrid())
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    let connection = SheetConnection(settings: settings, sync: sync, onSynced: {})

    let picked = Task { await connection.connect(SheetSelection(spreadsheetId: "picked-sheet", title: "Picked")) }
    await client.waitUntilHeld()
    let pastedMessage = await connection.connect(SheetSelection(spreadsheetId: "pasted-sheet"))
    client.release()
    let pickedMessage = await picked.value

    #expect(pastedMessage == "A sync is already in progress.")
    #expect(pickedMessage == nil)
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
private func seedStaleBlock(tabName: String, into context: ModelContext) {
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
                                    baseName: "Squat",
                                    cadence: nil,
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
    // swiftlint:disable:next force_try
    try! context.save()
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

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
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
