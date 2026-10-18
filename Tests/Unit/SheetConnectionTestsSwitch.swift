import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

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
