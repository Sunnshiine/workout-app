import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func loggingSetStartsConfiguredStandardRestTimer() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210))
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(restTimer.label == "Rest")
}

@MainActor
@Test func loggingSetInSupersetStartsConfiguredSupersetRestTimer() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210, superset: 45))
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_045))
    #expect(restTimer.remaining == 45)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(restTimer.label == "Superset rest")
}

@MainActor
@Test func loggingEachSupersetSetRestartsSupersetRestTimer() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210, superset: 45))
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let rowSet = try #require(row.sets.first)

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    clock.now.addTimeInterval(10)
    coordinator.log(rowSet, as: SetLog(weight: .pounds(95), reps: 10, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_055))
    #expect(restTimer.remaining == 45)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(restTimer.restartRevision == 2)
    #expect(restTimer.label == "Superset rest")
}

@MainActor
@Test func loggingAnotherSetRestartsExistingRestTimer() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210))
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let rowSet = try #require(session.exercises.first { $0.order == 2 }?.sets.first)

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    clock.now.addTimeInterval(60)
    coordinator.log(rowSet, as: SetLog(weight: .pounds(95), reps: 10, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_270))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(restTimer.restartRevision == 2)
}

@MainActor
@Test func deletingOriginSetCancelsRunningRestTimer() throws {
    let fixture = try makeRestActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    fixture.coordinator.deleteLog(for: secondBenchSet)

    #expect(fixture.restTimer.isRunning)

    fixture.coordinator.deleteLog(for: firstBenchSet)

    #expect(fixture.restTimer.interval == nil)
    #expect(fixture.restTimer.origin == nil)
    #expect(!fixture.restTimer.isRunning)
}

@MainActor
@Test func deletingMatchingSetInDifferentSessionDoesNotCancelRunningRestTimer() {
    let current = makeSingleSetSession(dayNumber: 1)
    let other = makeSingleSetSession(dayNumber: 2)
    connectCoordinatorWeek([current.session, other.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: current.session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210))
    )

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(restTimer.isRunning)

    other.set.state = .logged
    other.set.setLog = SetLog(weight: .pounds(95), reps: 10, rpe: .seven)
    coordinator.deleteLog(for: other.set)

    #expect(restTimer.isRunning)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
}

@MainActor
@Test func cancellingSessionRestForMoveOnDismissesRunningRestTimer() throws {
    let liveActivity = SpySessionLiveActivityAdapter()
    let fixture = try makeRestActionFixture(liveActivity: liveActivity)
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    fixture.coordinator.cancelRestForSessionExit()

    #expect(fixture.restTimer.interval == nil)
    #expect(fixture.restTimer.origin == nil)
    #expect(!fixture.restTimer.isRunning)
    #expect(liveActivity.endCallCount == 1)
}

@MainActor
@Test func moveOnEndsTheRestBeforeItAsksForTheCelebration() throws {
    let session = makeCoordinatorSession()
    let restTimer = RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000)))
    let liveActivity = SpySessionLiveActivityAdapter()
    let navigation = SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) })
    navigation.readAtCelebrationRequest = { restTimer.isRunning }
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: navigation,
            sync: SpySessionSyncAdapter(),
            restTimer: restTimer,
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(restTimer.isRunning)

    coordinator.moveOn()

    #expect(navigation.celebrationRequests == [false])
    #expect(liveActivity.endCallCount == 1)
}

@MainActor
@Test func loggingLastCurrentWeekPendingSetDoesNotStartRestTimer() throws {
    let current = makeSingleSetSession(dayNumber: 1)
    connectCoordinatorWeek([current.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: current.session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210))
    )

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval == nil)
    #expect(restTimer.origin == nil)
    #expect(logging.loggedSets.map(\.set) == [current.set])
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func loggingDayLastSetStartsRestWhenMakeupOpenExerciseRemains() throws {
    let current = makeSingleSetSession(dayNumber: 1)
    let makeup = makeSingleSetSession(dayNumber: 2)
    connectCoordinatorWeek([current.session, makeup.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: current.session,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210))
    )

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func bindingSheetOriginLogsDoesNotStartRestTimer() {
    let current = makeSingleSetSession(dayNumber: 1)
    current.set.state = .logged
    current.set.unstructuredSetLog = "185 for reps"
    connectCoordinatorWeek([current.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: nil,
        wiring: .fixture(logging: logging, sync: sync, restTimer: restTimer, restDurations: restDurations(standard: 210))
    )

    coordinator.view(current.session)

    #expect(restTimer.interval == nil)
    #expect(logging.loggedSets.isEmpty)
    #expect(sync.flushRequestCount == 0)
}

@MainActor
@Test func editSkipAndDeleteDoNotStartRestTimer() throws {
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    let editFixture = try makeRestActionFixture()
    let squatSet = try #require(editFixture.session.exercises.first { $0.order == 0 }?.sets.first)
    editFixture.coordinator.updateLoggedSet(squatSet, as: log)
    #expect(editFixture.restTimer.interval == nil)

    let skipFixture = try makeRestActionFixture()
    let skipSet = try #require(skipFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    skipFixture.coordinator.skip(skipSet)
    #expect(skipFixture.restTimer.interval == nil)

    let deleteFixture = try makeRestActionFixture()
    let deleteSet = try #require(deleteFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    deleteSet.state = .logged
    deleteSet.setLog = log
    deleteFixture.coordinator.deleteLog(for: deleteSet)
    #expect(deleteFixture.restTimer.interval == nil)
}

@MainActor
@Test func sessionRestsStartAtTheSettingsStoreDefaultsWhenNothingWasChosen() throws {
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
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.remaining == 120)

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })
    coordinator.log(secondBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .eight))

    #expect(restTimer.remaining == 30)
}

@MainActor
@Test func aRestLengthChangedMidSessionTakesEffectOnTheNextSet() throws {
    let session = makeCoordinatorSession()
    let restTimer = RestTimer(
        clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000)),
        expiryScheduler: HeldRestExpiry()
    )
    let settings = restDurations(standard: 120)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: SpySessionLoggingAdapter(), restTimer: restTimer, restDurations: settings)
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(restTimer.remaining == 120)
    restTimer.dismiss()

    settings.setStandardRestDuration(RestDurationSetting(seconds: 180))
    coordinator.log(secondBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .eight))

    #expect(restTimer.remaining == 180)
}
