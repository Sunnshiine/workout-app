import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

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
