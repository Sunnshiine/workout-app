import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func withOnDiskStore(weekCount: Int, _ body: (WorkoutStore, ModelContext) throws -> Void) async throws {
    try await withOnDiskStoreFile { url in
        let container = try ModelContainer(
            for: Block.self,
            PendingWrite.self,
            WriteTargetAuditEntry.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        context.insert(makeStoreBlock(weekCount: weekCount))
        try context.save()
        let store = WorkoutStore(context: context, defaults: .inMemory())
        store.reload()
        try withExtendedLifetime(container) { try body(store, context) }
    }
}

/// `SyncCoordinator.replacePersistedBlock` inlined, then the reload `SheetConnection` runs after
/// every sync.
@MainActor
private func sync(
    _ store: WorkoutStore,
    replacingBlockWith block: Block,
    in context: ModelContext,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for existing in try context.fetch(FetchDescriptor<Block>()) { context.delete(existing) }
    context.insert(block)
    try context.save()
    store.reload()
    expectShowsOnlySessionsOfItsBlock(store, sourceLocation: sourceLocation)
}

@MainActor
@Test func reloadKeepsTheBrowsedSessionWhenTheSyncReplacesTheWholeBlock() async throws {
    try await withOnDiskStore(weekCount: 2) { store, context in
        store.show(SessionAddress(week: 2, day: 3))
        #expect(store.viewedSession?.week?.number == 2)

        try sync(store, replacingBlockWith: makeStoreBlock(weekCount: 2), in: context)

        #expect(store.viewedSession?.week?.number == 2)
        #expect(store.viewedSession?.dayNumber == 3)
    }
}

@MainActor
@Test func reloadReturnsToTheCurrentSessionWhenTheBrowsedSessionLeavesTheBlock() async throws {
    try await withOnDiskStore(weekCount: 1) { store, context in
        store.show(SessionAddress(week: 1, day: 4))
        #expect(store.viewedSession?.dayNumber == 4)

        try sync(store, replacingBlockWith: makeStoreBlock(dayCount: 3), in: context)

        #expect(store.viewedSession?.dayNumber == 1)
        #expect(store.isViewingLiveEdge)
    }
}

@MainActor
@Test func dismissingMoveOnCelebrationAfterASyncAdvancesFromTheCelebratedSession() async throws {
    try await withOnDiskStore(weekCount: 2) { store, context in
        store.show(SessionAddress(week: 2, day: 3))
        store.makeViewedSessionCurrent()
        store.requestMoveOnCelebration()

        try sync(store, replacingBlockWith: makeStoreBlock(weekCount: 2), in: context)
        #expect(store.moveOnCelebrationSession?.address == SessionAddress(week: 2, day: 3))
        store.dismissMoveOnCelebration()

        #expect(store.currentSession?.address == SessionAddress(week: 2, day: 4))
        #expect(store.viewedSession?.address == SessionAddress(week: 2, day: 4))
    }
}

@MainActor
@Test func aSyncThatRemovesTheCelebratedSessionEndsTheCelebrationWithoutMovingOn() async throws {
    try await withOnDiskStore(weekCount: 2) { store, context in
        store.show(SessionAddress(week: 2, day: 3))
        store.makeViewedSessionCurrent()
        store.requestMoveOnCelebration()

        try sync(store, replacingBlockWith: makeStoreBlock(weekCount: 2, dayCount: 2), in: context)
        #expect(store.moveOnCelebrationSession == nil)
        #expect(store.moveOnCelebrationRequestedAt == nil)
        store.dismissMoveOnCelebration()

        #expect(store.currentSession?.address == SessionAddress(week: 1, day: 1))
    }
}

private enum SetWrite: CaseIterable {
    case log
    case skip
    case deleteLog
    case editLog

    static let firstLog = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)

    var needsALoggedSet: Bool { self == .deleteLog || self == .editLog }

    @MainActor
    func run(on store: WorkoutStore, _ set: ExerciseSet) throws {
        switch self {
        case .log: try store.log(set, as: Self.firstLog)
        case .skip: try store.skip(set)
        case .deleteLog: try store.deleteLog(for: set)
        case .editLog: try store.log(set, as: SetLog(weight: .pounds(190), reps: 4, rpe: .nine))
        }
    }
}

/// The write path refuses a Set the sync took out of the Block, whichever links the cascade delete
/// left it, and leaves the Set as the athlete last saw it.
@MainActor
@Test(arguments: SetWrite.allCases)
private func writingASetHeldAcrossASyncQueuesNoWrite(_ write: SetWrite) async throws {
    try await withOnDiskStore(weekCount: 1) { store, context in
        let held = try #require(store.currentSession?.exercises.first?.sets.first)
        if write.needsALoggedSet { try store.log(held, as: SetWrite.firstLog) }
        let queued = try context.fetchCount(FetchDescriptor<PendingWrite>())
        let (state, setLog) = (held.state, held.setLog)
        try sync(store, replacingBlockWith: makeStoreBlock(), in: context)

        #expect(throws: WorkoutLoggingError.detachedSession) { try write.run(on: store, held) }
        #expect(try context.fetchCount(FetchDescriptor<PendingWrite>()) == queued)
        #expect(held.state == state)
        #expect(held.setLog == setLog)
    }
}

/// A Set the sync took out of the Block reads every link up to the Block it left in about one run
/// in eighty (#1036), so the test above meets it only now and then. A Set of a Block the store
/// does not hold is that Set on every run.
@MainActor
@Test(arguments: SetWrite.allCases)
private func writingASetOfABlockTheStoreDoesNotHoldQueuesNoWrite(_ write: SetWrite) throws {
    let fixture = try makeStore()
    let otherBlock = makeStoreBlock(tabName: "Block 28")
    let other = try #require(otherBlock.weeks.first?.sessions.first?.exercises.first?.sets.first)
    if write.needsALoggedSet { other.markLogged(SetWrite.firstLog, at: Date(timeIntervalSinceReferenceDate: 0)) }
    let (state, setLog) = (other.state, other.setLog)

    #expect(throws: WorkoutLoggingError.detachedSession) { try write.run(on: fixture.store, other) }
    #expect(try fixture.container.mainContext.fetchCount(FetchDescriptor<PendingWrite>()) == 0)
    #expect(other.state == state)
    #expect(other.setLog == setLog)
}
