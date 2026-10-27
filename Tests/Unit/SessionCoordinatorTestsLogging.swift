import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func updatingLoggedSetUsesAdaptersWithoutAdvancingActivePendingSet() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)

    #expect(fixture.logging.loggedSets.count == 1)
    #expect(fixture.logging.loggedSets.first?.set === squatSet)
    #expect(fixture.logging.loggedSets.first?.log == updatedLog)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.coordinator.expandedLoggedSetID == nil)
    #expect(exerciseStage(fixture.coordinator, in: fixture.session)?.card?.cardIdentity == "stage-active-1-0")
    #expect(fixture.coordinator.savedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func openingTheReviewOfASetJustLoggedRendersItExpanded() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    fixture.coordinator.focus(on: firstBenchSet)

    let card = try #require(exerciseStage(fixture.coordinator, in: fixture.session)?.card)
    #expect(card.cardIdentity == "stage-review-1-0")
    #expect(card.mode == .reviewingLogged(showsSavedConfirmation: false))
}

@MainActor
@Test func aLogFromTheActiveCardLogsTheSetAndAdvancesTheCard() throws {
    let fixture = try makeActionFixture()
    let firstBenchSet = try #require(fixture.session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })
    let slot = try #require(exerciseStage(fixture.coordinator, in: fixture.session)?.card)
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    fixture.coordinator.log(log, for: slot)

    #expect(fixture.logging.loggedSets.map(\.set) == [firstBenchSet])
    #expect(fixture.logging.loggedSets.map(\.log) == [log])
    #expect(exerciseStage(fixture.coordinator, in: fixture.session)?.card?.cardIdentity == "stage-active-1-1")
    #expect(fixture.coordinator.savedLoggedSetID == nil)
}

@MainActor
@Test func aLogFromTheReviewCardUpdatesTheLoggedSetAndCollapsesTheReview() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    fixture.coordinator.focus(on: squatSet)
    let slot = try #require(exerciseStage(fixture.coordinator, in: fixture.session)?.card)
    let log = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)

    fixture.coordinator.log(log, for: slot)

    #expect(fixture.logging.loggedSets.map(\.set) == [squatSet])
    #expect(fixture.logging.loggedSets.map(\.log) == [log])
    #expect(exerciseStage(fixture.coordinator, in: fixture.session)?.card?.cardIdentity == "stage-active-1-0")
    #expect(fixture.coordinator.savedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func reopeningTheReviewOfASetJustUpdatedConfirmsTheSave() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: SetLog(weight: .pounds(205), reps: 5, rpe: .eight))
    fixture.coordinator.focus(on: squatSet)

    let card = try #require(exerciseStage(fixture.coordinator, in: fixture.session)?.card)
    #expect(card.cardIdentity == "stage-review-0-0")
    #expect(card.mode == .reviewingLogged(showsSavedConfirmation: true))
}

@MainActor
@Test func updatingPreviousLoggedSetDoesNotCollapseNewlyExpandedLoggedSet() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let rowSet = try #require(fixture.session.exercises.first { $0.order == 2 }?.sets.first)
    rowSet.state = .logged
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.focus(on: rowSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)

    #expect(fixture.coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(fixture.coordinator.savedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func bindingNewSessionClearsSavedLoggedSetFeedback() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)
    let next = makeSingleSetSession(dayNumber: 2)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)
    fixture.coordinator.view(next.session)

    #expect(fixture.coordinator.savedLoggedSetID == nil)
}

@MainActor
@Test func skippingSetUsesAdaptersAdvancesFocusAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.skip(firstBenchSet)

    #expect(fixture.logging.skippedSets.count == 1)
    #expect(fixture.logging.skippedSets.first === firstBenchSet)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func deletingSetLogUsesAdaptersFocusesDeletedSetAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    fixture.coordinator.log(firstBenchSet, as: log)

    fixture.coordinator.deleteLog(for: firstBenchSet)

    #expect(fixture.logging.deletedSets.count == 1)
    #expect(fixture.logging.deletedSets.first === firstBenchSet)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.sync.flushRequestCount == 2)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func loggingAdapterErrorReportsFailureWithoutAdvancingFocusOrFlushing() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    fixture.logging.error = .failed

    fixture.coordinator.log(firstBenchSet, as: log)

    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(firstBenchSet.state == .pending)
    #expect(fixture.sync.flushRequestCount == 0)
    #expect(fixture.sync.reportedErrors == ["failed"])
}

@MainActor
@Test func loggingSetFromDifferentSessionRebindsBeforeAdvancingFocus() throws {
    let old = makeSingleSetSession(dayNumber: 1)
    let new = makeSingleSetSession(dayNumber: 2)
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: old.session, wiring: .fixture(logging: logging, sync: sync))
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    coordinator.log(new.set, as: log)

    #expect(coordinator.sessionCoordinate == new.session.placement.coordinate)
    #expect(logging.loggedSets.first?.set === new.set)
    #expect(new.set.state == .logged)
    #expect(old.set.state == .pending)
    #expect(coordinator.activeSetID == nil)
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func deletingSetFromDifferentSessionRebindsBeforeFocusingDeletedSet() throws {
    let old = makeSingleSetSession(dayNumber: 1)
    let new = makeSingleSetSession(dayNumber: 2)
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: old.session, wiring: .fixture(logging: logging, sync: sync))
    new.set.state = .logged
    new.set.setLog = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    coordinator.deleteLog(for: new.set)

    #expect(coordinator.sessionCoordinate == new.session.placement.coordinate)
    #expect(logging.deletedSets.first === new.set)
    #expect(new.set.state == .pending)
    #expect(old.set.state == .pending)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func sessionScreenWiringSendsLogToTheBoundAdaptersAndRequestsFlush() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: logging,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: sync,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(logging.loggedSets.count == 1)
    #expect(logging.loggedSets.first?.log == SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(sync.flushRequestCount == 1)
    #expect(sync.reportedErrors.isEmpty)
}

@MainActor
@Test func sessionScreenWiringStartsBoundRestTimerWithTheBoundDurations() throws {
    let session = makeCoordinatorSession()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: SpySessionSyncAdapter(),
            restTimer: restTimer,
            restDurations: restDurations(standard: 123, superset: 77),
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.remaining == 123)
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_123))
    #expect(restTimer.label == "Rest")
}

@MainActor
@Test func sessionScreenWiringStartsBoundSupersetRestDurationForASupersetMember() throws {
    let session = makeCoordinatorSession()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: SpySessionSyncAdapter(),
            restTimer: restTimer,
            restDurations: restDurations(standard: 123, superset: 77),
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.remaining == 77)
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_077))
    #expect(restTimer.label == "Superset rest")
}
