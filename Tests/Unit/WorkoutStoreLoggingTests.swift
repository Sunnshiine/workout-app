import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func loggingContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "logging-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
private struct SeededLoggingStore {
    let store: WorkoutStore
    let context: ModelContext
    let firstSet: ExerciseSet
    let secondSet: ExerciseSet
    let container: ModelContainer
    let lookupStore: LastPerformedLookupStore
}

@MainActor
private final class ManualDateProvider {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class LoggedTimingSyncClient: SheetsClient, @unchecked Sendable {
    private let grid: SheetGrid

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        ["Block 27"]
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private func parsedLoggingBlock() -> ParsedBlockModel {
    ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    parsedSquatLoggingSession(),
                    parsedBenchMoveOnSession()
                ]
            )
        ]
    )
}

private func parsedSquatLoggingSession() -> ParsedSession {
    ParsedSession(
        dayNumber: 1,
        date: Date(timeIntervalSinceReferenceDate: 100),
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
                        prescribedLoad: "RPE 8",
                        percentOneRM: nil,
                        state: .pending,
                        setLog: nil
                    ),
                    ParsedSet(
                        index: 1,
                        prescribedReps: "5",
                        prescribedLoad: "RPE 9",
                        percentOneRM: nil,
                        state: .pending,
                        setLog: nil
                    )
                ]
            )
        ]
    )
}

private func parsedBenchMoveOnSession() -> ParsedSession {
    ParsedSession(
        dayNumber: 2,
        date: Date(timeIntervalSinceReferenceDate: 200),
        exercises: [
            ParsedExercise(
                name: "Bench Press",
                baseName: "Bench Press",
                cadence: nil,
                coachNote: nil,
                sets: [
                    ParsedSet(
                        index: 0,
                        prescribedReps: "5",
                        prescribedLoad: "RPE 8",
                        percentOneRM: nil,
                        state: .pending,
                        setLog: nil
                    )
                ]
            )
        ]
    )
}

@MainActor
private func makeLoggingDefaults() throws -> UserDefaults {
    let suiteName = "test.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func seededStore() throws -> SeededLoggingStore {
    try seededStore(now: Date.init)
}

@MainActor
private func seededStore(now: @escaping () -> Date) throws -> SeededLoggingStore {
    let container = try loggingContainer()
    let ctx = container.mainContext
    let block = BlockBuilder.makeBlock(from: parsedLoggingBlock())
    ctx.insert(block)
    try ctx.save()
    let lookupStore = LastPerformedLookupStore(context: ctx)
    let store = try WorkoutStore(
        context: ctx,
        defaults: makeLoggingDefaults(),
        lastPerformedLookupRefresher: lookupStore,
        now: now
    )
    store.reload()
    let set = try #require(
        store.block?.weeks.first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == 1 }?
            .exercises.first { $0.name == "Squat" }?
            .sets.sorted { $0.index < $1.index }
            .first
    )
    let secondSet = try #require(
        store.block?.weeks.first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == 1 }?
            .exercises.first { $0.name == "Squat" }?
            .sets.first { $0.index == 1 }
    )
    return SeededLoggingStore(
        store: store,
        context: ctx,
        firstSet: set,
        secondSet: secondSet,
        container: container,
        lookupStore: lookupStore
    )
}

@MainActor
@Test func loggingPendingSetRecordsFirstLoggedTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    #expect(fixture.firstSet.loggedAt == Date(timeIntervalSinceReferenceDate: 1_000))
}

@MainActor
@Test func updatingLoggedSetPreservesOriginalLoggedTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))
    dateProvider.now = Date(timeIntervalSinceReferenceDate: 1_500)
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 8.5))

    #expect(fixture.firstSet.loggedAt == Date(timeIntervalSinceReferenceDate: 1_000))
}

@MainActor
@Test func deletingSetLogClearsTimestampAndReloggingRecordsNewTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))
    try fixture.store.deleteLog(for: fixture.firstSet)
    #expect(fixture.firstSet.loggedAt == nil)

    dateProvider.now = Date(timeIntervalSinceReferenceDate: 1_500)
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 8.5))

    #expect(fixture.firstSet.loggedAt == Date(timeIntervalSinceReferenceDate: 1_500))
}

@MainActor
@Test func skippingSetDoesNotRecordLoggedTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}

    try fixture.store.skip(fixture.firstSet)

    #expect(fixture.firstSet.loggedAt == nil)
}

@MainActor
@Test func skippingLoggedSetClearsLoggedTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    try fixture.store.skip(fixture.firstSet)

    #expect(fixture.firstSet.loggedAt == nil)
}

@MainActor
@Test func requestingMoveOnCelebrationCapturesRequestTimeWithFirstSessionLog() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    dateProvider.now = Date(timeIntervalSinceReferenceDate: 1_900)
    fixture.store.requestMoveOnCelebration()

    #expect(
        fixture.store.moveOnCelebrationTiming
            == MoveOnCelebrationTiming(
                firstLoggedAt: Date(timeIntervalSinceReferenceDate: 1_000),
                requestedAt: Date(timeIntervalSinceReferenceDate: 1_900)
            )
    )
}

@MainActor
@Test func requestingMoveOnCelebrationLeavesTimingUnavailableWithoutLocalLogTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_900))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}

    fixture.store.requestMoveOnCelebration()

    #expect(fixture.store.moveOnCelebrationSession != nil)
    #expect(fixture.store.moveOnCelebrationTiming == nil)
}

@MainActor
@Test func requestingMoveOnCelebrationLeavesTimingUnavailableWhenAnyLoggedSetLacksLocalTimestamp() throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}
    fixture.firstSet.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: 8)
    fixture.firstSet.state = .logged

    dateProvider.now = Date(timeIntervalSinceReferenceDate: 1_500)
    try fixture.store.log(fixture.secondSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 8.5))
    dateProvider.now = Date(timeIntervalSinceReferenceDate: 1_900)
    fixture.store.requestMoveOnCelebration()

    #expect(fixture.store.moveOnCelebrationSession != nil)
    #expect(fixture.store.moveOnCelebrationTiming == nil)
}

@MainActor
@Test func syncReplacementPreservesLoggedTimestampForMoveOnTimingAfterFlush() async throws {
    let dateProvider = ManualDateProvider(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let fixture = try seededStore(now: { dateProvider.now })
    withExtendedLifetime(fixture.container) {}
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))
    for write in try fixture.context.fetch(FetchDescriptor<PendingWrite>()) {
        fixture.context.delete(write)
    }
    try fixture.context.save()
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE 8", "K15": "185x5@8",
            "T14": "Sets", "V14": "Reps", "X14": "Load",
            "S15": "Bench Press", "T15": "1", "V15": "5", "X15": "RPE 8"
        ],
        rows: 24,
        cols: 60
    )
    let sync = SyncCoordinator(
        client: LoggedTimingSyncClient(grid: grid),
        context: fixture.context,
        lastPerformedLookupRefresher: fixture.lookupStore
    )

    await sync.sync(spreadsheetId: "sid")
    fixture.store.reload()
    dateProvider.now = Date(timeIntervalSinceReferenceDate: 1_900)
    fixture.store.requestMoveOnCelebration()

    #expect(
        fixture.store.moveOnCelebrationTiming
            == MoveOnCelebrationTiming(
                firstLoggedAt: Date(timeIntervalSinceReferenceDate: 1_000),
                requestedAt: Date(timeIntervalSinceReferenceDate: 1_900)
            )
    )
}

@MainActor
@Test func logSetOptimisticallyUpdatesLocalSetAndQueuesWrite() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    try fixture.store.log(fixture.firstSet, as: log)

    #expect(fixture.firstSet.state == .logged)
    #expect(fixture.firstSet.setLog?.formatted == "185x5@8")
    let writes = try fixture.context.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    #expect(writes[0].column == .notes)
    #expect(writes[0].valueToWrite == "185x5@8")
    #expect(writes[0].expectedCurrentValue == "")
}

@MainActor
@Test func loggingFinalSetQueuesLastSetRPEWrite() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    let finalSet = try #require(fixture.firstSet.exercise?.sets.first { $0.index == 1 })

    try fixture.store.log(finalSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 9))

    let writes = try fixture.context.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.contains { $0.column == .lastSetRPE && $0.valueToWrite == "9" })
}

@MainActor
@Test func editingLoggedSetQueuesWriteLockedToPreviousSetLog() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 8.5))

    let pending = try #require(try fixture.context.fetch(FetchDescriptor<PendingWrite>()).last)
    #expect(pending.operation == .upsert)
    #expect(pending.column == .notes)
    #expect(pending.valueToWrite == "195x5@8.5")
    #expect(pending.expectedCurrentValue == "185x5@8")
}

@MainActor
@Test func editingUnstructuredSetLogQueuesWriteLockedToRawNotesValue() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    fixture.firstSet.state = .logged
    fixture.firstSet.unstructuredSetLog = "185, 185, backed off"

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    #expect(fixture.firstSet.setLog?.formatted == "185x5@8")
    #expect(fixture.firstSet.unstructuredSetLog == nil)
    let pending = try #require(try fixture.context.fetch(FetchDescriptor<PendingWrite>()).last)
    #expect(pending.operation == .upsert)
    #expect(pending.column == .notes)
    #expect(pending.valueToWrite == "185x5@8")
    #expect(pending.expectedCurrentValue == "185, 185, backed off")
}

@MainActor
@Test func deleteSetClearsLocalSetAndQueuesDelete() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    try fixture.store.deleteLog(for: fixture.firstSet)

    #expect(fixture.firstSet.state == .pending)
    #expect(fixture.firstSet.setLog == nil)
    let pending = try #require(try fixture.context.fetch(FetchDescriptor<PendingWrite>()).last)
    #expect(pending.operation == .delete)
    #expect(pending.expectedCurrentValue == "185x5@8")
}

@MainActor
@Test func logSetUpdatesLastPerformedIndexForExercise() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    let index = LastPerformedIndex(context: fixture.context)
    let entry = try #require(index.lookup(exerciseName: "Squat", baseName: "Squat"))
    #expect(entry.result == SetLog(weight: .pounds(185), reps: 5, rpe: 8))
    #expect(entry.performedOn == Date(timeIntervalSinceReferenceDate: 100))
    #expect(entry.source == "Block 27 · W1 D1")
}

@MainActor
@Test func logSetRefreshesLastPerformedLookupSnapshotForDisplay() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}

    #expect(
        fixture.lookupStore.snapshot.lookup(
            exerciseName: "Squat",
            baseName: "Squat"
        ) == nil
    )

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    let entry = try #require(
        fixture.lookupStore.snapshot.lookup(
            exerciseName: "Squat",
            baseName: "Squat"
        )
    )
    #expect(entry.resultText == "185x5@8")
    #expect(entry.sourceText == "Block 27 · W1 D1")
}

@MainActor
@Test func skipSetDoesNotWriteLastPerformedEntry() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}

    try fixture.store.skip(fixture.firstSet)

    let index = LastPerformedIndex(context: fixture.context)
    #expect(index.lookup(exerciseName: "Squat", baseName: "Squat") == nil)
}
