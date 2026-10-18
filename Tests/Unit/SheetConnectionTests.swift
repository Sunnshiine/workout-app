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
func makeCacheSafetyContainer() throws -> ModelContainer {
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
func queueReplacementSquatLog(
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

final class RecordingSheetsClient: SheetsClient, @unchecked Sendable {
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
final class StubSheetSwitchSync: SheetSwitchSyncing {
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

enum StubSheetSwitchError: Error {
    case discardFailed
    case pendingWriteLookupFailed
}
