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

/// The write path refuses a Set the sync took out of the Block, whichever link the store dropped.
@MainActor
@Test func loggingASetHeldAcrossASyncQueuesNoWrite() async throws {
    try await withOnDiskStore(weekCount: 1) { store, context in
        let held = try #require(store.currentSession?.exercises.first?.sets.first)
        try sync(store, replacingBlockWith: makeStoreBlock(), in: context)

        #expect(throws: WorkoutLoggingError.self) {
            try store.log(held, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        }
        #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    }
}
