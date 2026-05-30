import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct PartiallyUploadedBlockStoreFixture {
    let store: WorkoutStore
    let container: ModelContainer
}

@MainActor
private func makePartiallyUploadedBlockStore() throws -> PartiallyUploadedBlockStoreFixture {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        configurations: ModelConfiguration(
            "partially-uploaded-block-store-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let context = container.mainContext
    context.insert(WorkoutFixtureScenarios.partiallyUploadedBlock())
    try context.save()

    let suiteName = "partial-block-store.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = WorkoutStore(context: context, defaults: defaults)
    store.reload()
    return PartiallyUploadedBlockStoreFixture(store: store, container: container)
}

@MainActor
@Test func moveOnSkipsUnavailableSessionsInPartiallyUploadedBlock() throws {
    let fixture = try makePartiallyUploadedBlockStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 2)

    store.moveOn()
    #expect(store.currentSession?.week?.number == 2)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.displayedSession?.week?.number == 2)
    #expect(store.displayedSession?.dayNumber == 1)
}

@MainActor
@Test func lastAvailableSessionCanMoveOnToBlockOverviewWhenUnavailableSessionsRemainAhead() throws {
    let fixture = try makePartiallyUploadedBlockStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.moveOn()
    store.moveOn()
    store.moveOn()

    #expect(store.currentSession?.week?.number == 4)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.canMoveOn)

    store.requestMoveOnCelebration()
    #expect(store.moveOnCelebrationSession?.week?.number == 4)
    #expect(store.moveOnCelebrationSession?.dayNumber == 1)

    store.dismissMoveOnCelebration()

    #expect(store.moveOnCelebrationSession == nil)
    #expect(store.currentSession?.week?.number == 4)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.displayedSession?.week?.number == 4)
    #expect(store.displayedSession?.dayNumber == 1)
    #expect(store.pendingBlockOverviewRequest != nil)

    store.clearBlockOverviewRequest()
    #expect(store.pendingBlockOverviewRequest == nil)
}
