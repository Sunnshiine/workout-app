import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

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
@Test func moveOnFromTheLastSessionReturnsToTheBlockGrid() throws {
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
    #expect(store.canMoveOn)

    store.moveOn()

    #expect(store.pendingBlockOverviewRequest != nil)
}
