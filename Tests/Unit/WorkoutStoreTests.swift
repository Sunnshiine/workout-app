import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct WorkoutStoreFixture {
    let store: WorkoutStore
    let container: ModelContainer
}

@MainActor
private func makeStoreBlock(tabName: String = "Block 27", weekCount: Int = 1, dayCount: Int = 4) -> Block {
    BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: tabName,
            weeks: (1...weekCount).map { week in
                ParsedWeek(
                    number: week,
                    days: (1...dayCount).map { day in
                        ParsedSession(
                            dayNumber: day,
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
                                            percentOneRM: nil
                                        )
                                    ]
                                )
                            ]
                        )
                    }
                )
            }
        )
    )
}

@MainActor
private func makeStore(
    tabName: String = "Block 27",
    weekCount: Int = 1,
    defaults: AppDefaults = .inMemory(),
    lastPerformed: any LastPerformedIndexing = NoopLastPerformedIndex(),
    now: @escaping @MainActor () -> Date = Date.init
) throws -> WorkoutStoreFixture {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(
            "workout-store-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let ctx = container.mainContext
    ctx.insert(makeStoreBlock(tabName: tabName, weekCount: weekCount))
    try ctx.save()
    let store = WorkoutStore(context: ctx, defaults: defaults, lastPerformed: lastPerformed, now: now)
    store.reload()
    return WorkoutStoreFixture(store: store, container: container)
}

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
@Test func loadsBlockAndDefaultsViewedToCurrent() throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: (1...1).map { w in
            ParsedWeek(
                number: w,
                days: (1...4).map { d in
                    ParsedSession(dayNumber: d, date: nil, exercises: [])
                }
            )
        }
    )
    ctx.insert(BlockBuilder.makeBlock(from: parsed))
    try ctx.save()

    let store = WorkoutStore(context: ctx, defaults: .inMemory())
    store.reload()

    #expect(store.block?.tabName == "Block 27")
    #expect(store.viewedSession == nil)
    store.show(SessionAddress(week: 1, day: 3))
    #expect(store.viewedSession?.dayNumber == 3)
}

@MainActor
@Test func openExercisesDelegatesToCurrentBlockAndCurrentSession() throws {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(
            "open-exercises-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.insert(WorkoutScenarios.openExercises().block)
    try context.save()

    let store = WorkoutStore(context: context, defaults: .inMemory())
    store.reload()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.openExercises.map(\.exerciseName.entered) == ["Back Squat", "Bench Press"])
}

@MainActor
@Test func reloadPreservesViewedSessionWhenStillPresent() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.show(SessionAddress(week: 1, day: 3))
    store.reload()

    #expect(store.viewedSession?.week?.number == 1)
    #expect(store.viewedSession?.dayNumber == 3)
}

@MainActor
@Test func reloadKeepsTheBrowsedSessionWhenTheCurrentSessionMovesUnderIt() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day2Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 2 }?.exercises[0].sets[0])

    store.show(SessionAddress(week: 1, day: 4))
    day2Set.state = .logged
    store.reload()

    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.viewedSession?.dayNumber == 4)
    #expect(!store.isViewingLiveEdge)
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
@Test func reloadAdvancesViewedSessionWhenViewingCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])

    day3Set.state = .logged
    store.reload()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.viewedSession?.dayNumber == 3)
}

@MainActor
@Test func showCurrentResetsViewedSessionToCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3 = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 })
    day3.exercises[0].sets[0].state = .logged
    store.reload()

    store.show(SessionAddress(week: 1, day: 1))
    #expect(store.viewedSession?.dayNumber == 1)

    store.showCurrent()

    #expect(store.viewedSession?.dayNumber == 3)
    #expect(store.isViewingLiveEdge)
}

@MainActor
@Test func showingSessionDoesNotChangeCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.show(SessionAddress(week: 1, day: 3))

    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.viewedSession?.dayNumber == 3)
    #expect(!store.isViewingLiveEdge)
}

@MainActor
@Test func makeViewedSessionCurrentCanTargetSessionBehindLoggedProgress() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()
    #expect(store.currentSession?.dayNumber == 3)

    store.show(SessionAddress(week: 1, day: 1))
    store.makeViewedSessionCurrent()

    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.viewedSession?.dayNumber == 1)
    #expect(store.isViewingLiveEdge)
}

@MainActor
@Test func ignoresLegacyOrderOverrideKeyFromBeforeStrideChange() throws {
    // A pre-V2 build persisted the Current Session Pin under "advancedToOrder_<tab>"
    // with the old stride-4 encoding. Under the new stride-7 encoding that same integer can map
    // to a DIFFERENT Session, so the new key must ignore the legacy value and fall back to the
    // derived Current Session rather than silently resolving to the wrong one.
    let defaults = AppDefaults.inMemory()
    defaults.set(8, forKey: "advancedToOrder_Block 27")  // legacy W2 D4; = W2 D1 under stride 7

    let fixture = try makeStore(weekCount: 2, defaults: defaults)
    defer { withExtendedLifetime(fixture.container) {} }

    // Nothing is logged, so the derived Current Session is W1 D1 — not the legacy value's target.
    #expect(fixture.store.currentSession?.week?.number == 1)
    #expect(fixture.store.currentSession?.dayNumber == 1)
}

@MainActor
@Test func reloadPreservesManualCurrentSessionOverrideAgainstSheetDerivedProgress() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()

    store.show(SessionAddress(week: 1, day: 1))
    store.makeViewedSessionCurrent()
    store.reload()

    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.viewedSession?.dayNumber == 1)
}

@MainActor
@Test func makingViewedSessionCurrentDoesNotQueueSheetWrite() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.show(SessionAddress(week: 1, day: 2))
    store.makeViewedSessionCurrent()

    let writes = try fixture.container.mainContext.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.isEmpty)
}

@MainActor
@Test func currentSessionDebugInfoShowsSheetDerivedResolutionWhenNoPin() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()

    store.show(SessionAddress(week: 1, day: 1))

    let info = store.currentSessionDebugInfo

    #expect(info.currentBlockTab == "Block 27")
    #expect(info.sheetDerivedSession == "Week 1, Day 3")
    #expect(info.pinnedSession == "None")
    #expect(info.viewedSession == "Week 1, Day 1")
    #expect(info.resolvedCurrentSession == "Week 1, Day 3")
    #expect(info.reason == "No Current Session Pin is set, so Sheet-derived progress wins.")
    #expect(info.localOnlyNote == nil)
    #expect(info.copyText.contains("Sheet-derived Session: Week 1, Day 3"))
}

@MainActor
@Test func currentSessionDebugInfoShowsLocalOnlyPinWhenPresent() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()

    store.show(SessionAddress(week: 1, day: 1))
    store.makeViewedSessionCurrent()

    let info = store.currentSessionDebugInfo

    #expect(info.sheetDerivedSession == "Week 1, Day 3")
    #expect(info.pinnedSession == "Week 1, Day 1 (Make current)")
    #expect(info.viewedSession == "Week 1, Day 1")
    #expect(info.resolvedCurrentSession == "Week 1, Day 1")
    #expect(info.reason == "The athlete made this Session current, so it wins over Sheet-derived progress.")
    #expect(info.localOnlyNote == "The Current Session Pin is local-only and is not Sheet data.")
    #expect(info.canClearPin)
    #expect(info.copyText.contains("Current Session Pin: Week 1, Day 1 (Make current)"))
    #expect(info.copyText.contains("The Current Session Pin is local-only and is not Sheet data."))
}

@MainActor
@Test func currentSessionDebugInfoNarratesAMoveOnAsAPinNotAnOverride() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()

    let info = store.currentSessionDebugInfo
    #expect(info.pinnedSession == "Week 1, Day 2 (Move On)")
    #expect(info.resolvedCurrentSession == "Week 1, Day 2")
    #expect(info.reason == "Move On advanced to this Session, so it wins over Sheet-derived progress.")
    #expect(info.localOnlyNote == "The Current Session Pin is local-only and is not Sheet data.")
    #expect(info.canClearPin)
}

@MainActor
@Test func currentSessionDebugInfoNarratesAPinOnASessionThatBecameUnavailable() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    store.show(SessionAddress(week: 1, day: 2))
    store.makeViewedSessionCurrent()

    let pinned = try #require(store.block?.session(at: SessionAddress(week: 1, day: 2)))
    pinned.exercises = []
    store.reload()

    let info = store.currentSessionDebugInfo
    #expect(store.currentSession?.dayNumber == 1)
    #expect(info.pinnedSession == "Week 1, Day 2, Unavailable (Make current)")
    #expect(info.resolvedCurrentSession == "Week 1, Day 1")
    #expect(info.reason == "The Current Session Pin names an Unavailable Session, so Sheet-derived progress wins.")
    #expect(info.localOnlyNote == nil)
    #expect(info.canClearPin)
}

@MainActor
@Test func currentSessionDebugInfoNarratesAPinThatNoLongerMatchesTheBlock() throws {
    let defaults = AppDefaults.inMemory()
    defaults.set(99, forKey: "advancedToOrderV2_Block 27")
    let fixture = try makeStore(defaults: defaults)
    defer { withExtendedLifetime(fixture.container) {} }

    let info = fixture.store.currentSessionDebugInfo

    #expect(fixture.store.currentSession?.dayNumber == 1)
    #expect(info.pinnedSession == "Saved pin no longer matches this Block (Move On)")
    #expect(info.reason == "The Current Session Pin no longer matches this Block, so Sheet-derived progress wins.")
    #expect(info.localOnlyNote == nil)
    #expect(info.canClearPin)
}

@MainActor
@Test func currentSessionDebugInfoNarratesABlockWithNoAvailableSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let block = try #require(store.block)
    for session in block.weeks.flatMap(\.sessions) {
        session.exercises = []
    }
    store.reload()

    let info = store.currentSessionDebugInfo

    #expect(info.sheetDerivedSession == "None")
    #expect(info.resolvedCurrentSession == "None")
    #expect(info.reason == "No Sheet-derived Session is available for this Block.")
    #expect(!info.canClearPin)
}

@MainActor
@Test func clearingThePinReturnsViewedSessionToSheetDerivedWithoutSheetWrite() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()
    store.show(SessionAddress(week: 1, day: 1))
    store.makeViewedSessionCurrent()

    store.clearCurrentSessionPin()

    let info = store.currentSessionDebugInfo
    let writes = try fixture.container.mainContext.fetch(FetchDescriptor<PendingWrite>())
    #expect(info.pinnedSession == "None")
    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.viewedSession?.dayNumber == 3)
    #expect(writes.isEmpty)
}

@MainActor
@Test func clearingThePinDoesNotClearAnotherBlocksPin() throws {
    let defaults = AppDefaults.inMemory()
    let block27 = try makeStore(tabName: "Block 27", defaults: defaults)
    let block28 = try makeStore(tabName: "Block 28", defaults: defaults)
    defer {
        withExtendedLifetime(block27.container) {}
        withExtendedLifetime(block28.container) {}
    }
    block27.store.show(SessionAddress(week: 1, day: 2))
    block27.store.makeViewedSessionCurrent()
    block28.store.show(SessionAddress(week: 1, day: 3))
    block28.store.makeViewedSessionCurrent()

    block27.store.clearCurrentSessionPin()
    block28.store.reload()

    #expect(block27.store.currentSessionDebugInfo.pinnedSession == "None")
    #expect(block27.store.currentSession?.dayNumber == 1)
    #expect(block28.store.currentSessionDebugInfo.pinnedSession == "Week 1, Day 3 (Make current)")
    #expect(block28.store.currentSession?.dayNumber == 3)
}

@MainActor
@Test func moveOnAdvancesCurrentSessionAndViewedSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()

    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.viewedSession?.week?.number == 1)
    #expect(store.viewedSession?.dayNumber == 2)
}

@MainActor
@Test func moveOnAdvancesFromManualCurrentSessionOverride() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.show(SessionAddress(week: 1, day: 3))
    store.makeViewedSessionCurrent()
    store.moveOn()

    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 4)
    #expect(store.viewedSession?.week?.number == 1)
    #expect(store.viewedSession?.dayNumber == 4)
}

@MainActor
@Test func requestingMoveOnCelebrationCapturesCurrentSessionWithoutAdvancing() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.requestMoveOnCelebration()

    #expect(store.moveOnCelebrationSession?.week?.number == 1)
    #expect(store.moveOnCelebrationSession?.dayNumber == 1)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.viewedSession?.week?.number == 1)
    #expect(store.viewedSession?.dayNumber == 1)
}

@MainActor
@Test func requestingMoveOnCelebrationCapturesRequestTime() throws {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)
    let fixture = try makeStore(now: { now })
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    now = Date(timeIntervalSinceReferenceDate: 1_500)
    store.requestMoveOnCelebration()

    #expect(store.moveOnCelebrationRequestedAt == Date(timeIntervalSinceReferenceDate: 1_500))

    now = Date(timeIntervalSinceReferenceDate: 2_000)
    store.dismissMoveOnCelebration()

    #expect(store.moveOnCelebrationRequestedAt == nil)
}

@MainActor
@Test func dismissingMoveOnCelebrationAdvancesFromCapturedSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.requestMoveOnCelebration()
    store.dismissMoveOnCelebration()

    #expect(store.moveOnCelebrationSession == nil)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.viewedSession?.week?.number == 1)
    #expect(store.viewedSession?.dayNumber == 2)
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

@MainActor
@Test func reachingZeroLeftDoesNotShowCelebrationOrAdvanceCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let currentSet = try #require(store.currentSession?.exercises[0].sets[0])

    currentSet.state = .logged
    store.reload()

    let currentSession = try #require(store.currentSession)
    let presentation = SessionProgressHeaderPresentation(session: currentSession)
    #expect(presentation.remainingSetCount == 0)
    #expect(store.moveOnCelebrationSession == nil)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.viewedSession?.week?.number == 1)
    #expect(store.viewedSession?.dayNumber == 1)
}

@MainActor
@Test func moveOnAdvancePersistsAcrossReload() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.reload()

    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.viewedSession?.dayNumber == 2)
}

@MainActor
@Test func repeatedMoveOnsOverwriteStoredAdvance() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.moveOn()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.viewedSession?.dayNumber == 3)
}

@MainActor
@Test func moveOnCrossesWeekBoundaryAndDropsPriorWeekOpenExercises() throws {
    let fixture = try makeStore(weekCount: 2)
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.moveOn()
    store.moveOn()
    store.moveOn()

    #expect(store.currentSession?.week?.number == 2)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.openExercises.isEmpty)
}

@MainActor
@Test func loggedProgressPastStoredOverrideDoesNotReplaceCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])

    store.moveOn()
    try store.log(day3Set, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))

    #expect(store.currentSession?.dayNumber == 2)
}

@MainActor
@Test func canMoveOnIsFalseOnLastSession() throws {
    let fixture = try makeStore(weekCount: 4)
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let finalSet = try #require(
        store.block?.weeks.first { $0.number == 4 }?.sessions.first { $0.dayNumber == 4 }?.exercises[0].sets[0]
    )

    finalSet.state = .logged
    store.reload()

    #expect(store.currentSession?.week?.number == 4)
    #expect(store.currentSession?.dayNumber == 4)
    #expect(!store.canMoveOn)
}

@MainActor
@Test func theStoredCurrentSessionMatchesAFreshResolveAfterEveryWritePoint() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let sessions = try #require(store.block?.weeks.first?.sessions)
    func firstSet(ofDay day: Int) throws -> ExerciseSet {
        try #require(sessions.first { $0.dayNumber == day }?.exercises.first?.sets.first)
    }
    var stored: [String] = []
    func record() {
        let label = store.currentSession?.address.map { "Week \($0.week), Day \($0.day)" } ?? "None"
        #expect(label == store.currentSessionDebugInfo.resolvedCurrentSession)
        stored.append(label)
    }

    record()
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
    try store.log(try firstSet(ofDay: 2), as: log)
    record()
    try store.log(try firstSet(ofDay: 3), as: log)
    record()
    try store.skip(try firstSet(ofDay: 3))
    record()
    try store.deleteLog(for: try firstSet(ofDay: 2))
    record()
    store.reload()
    record()
    store.show(SessionAddress(week: 1, day: 2))
    store.makeViewedSessionCurrent()
    record()
    store.clearCurrentSessionPin()
    record()
    store.moveOn()
    record()

    #expect(
        stored == [
            "Week 1, Day 1", "Week 1, Day 2", "Week 1, Day 3", "Week 1, Day 2", "Week 1, Day 1",
            "Week 1, Day 1", "Week 1, Day 2", "Week 1, Day 1", "Week 1, Day 2"
        ]
    )
}

@MainActor
@Test func aWriteThatThrowsAfterMovingTheSetStillMovesTheStoredCurrentSession() throws {
    let fixture = try makeStore(lastPerformed: RefusingIndex())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let set = try #require(
        store.block?.weeks.first?.sessions.first { $0.dayNumber == 2 }?.exercises.first?.sets.first
    )

    #expect(throws: (any Error).self) {
        try store.log(set, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    }

    #expect(set.state == .logged)
    #expect(store.currentSession?.dayNumber == 2)
}

@MainActor
private final class CurrentSessionChanges {
    private(set) var count = 0

    init(watching store: WorkoutStore) {
        observe(store)
    }

    private func observe(_ store: WorkoutStore) {
        withObservationTracking {
            _ = store.currentSession
        } onChange: {
            MainActor.assumeIsolated {
                self.count += 1
                self.observe(store)
            }
        }
    }
}

@MainActor
@Test func observersHearTheCurrentSessionOnlyWhenItMoves() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let sessions = try #require(store.block?.weeks.first?.sessions)
    func firstSet(ofDay day: Int) throws -> ExerciseSet {
        try #require(sessions.first { $0.dayNumber == day }?.exercises.first?.sets.first)
    }
    let changes = CurrentSessionChanges(watching: store)
    var counts: [Int] = []

    store.reload()
    counts.append(changes.count)
    try store.log(try firstSet(ofDay: 1), as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    counts.append(changes.count)
    try store.log(try firstSet(ofDay: 2), as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    counts.append(changes.count)
    store.moveOn()
    counts.append(changes.count)

    #expect(counts == [0, 0, 1, 2])
}

/// The write path refuses a Set the sync took out of the Block, whichever link the store dropped.
@MainActor
@Test func loggingASetHeldAcrossASyncQueuesNoWrite() throws {
    try withOnDiskStore(weekCount: 1) { store, context in
        let held = try #require(store.currentSession?.exercises.first?.sets.first)
        try replaceBlock(in: context, with: makeStoreBlock())
        store.reload()

        #expect(throws: WorkoutLoggingError.self) {
            try store.log(held, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        }
        #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    }
}
