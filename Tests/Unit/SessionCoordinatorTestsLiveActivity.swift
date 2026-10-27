import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func loggingCurrentSessionSetStartsLiveActivityFromRestContent() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: logging,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: sync,
            restTimer: restTimer,
            restDurations: restDurations(standard: 210),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    let call = try #require(liveActivity.calls.first)
    #expect(liveActivity.calls.count == 1)
    #expect(liveActivity.invalidationCalls.count == 1)
    #expect(call.sessionLabel == "Week 1 - Day 1")
    #expect(call.content.exerciseName == "Bench Press")
    #expect(call.content.prescribedReps == "6")
    #expect(call.content.prescribedLoad == "RPE 8")
    #expect(call.content.setsDone == 1)
    #expect(call.content.setsTotal == 2)
    #expect(call.content.restStartDate == Date(timeIntervalSinceReferenceDate: 2_000))
    #expect(call.content.restEndDate == Date(timeIntervalSinceReferenceDate: 2_210))
}

@MainActor
@Test func loggingAnotherCurrentSessionSetRequestsLiveActivityStartOrUpdateAgain() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: logging,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: sync,
            restTimer: restTimer,
            restDurations: restDurations(standard: 210),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    clock.now.addTimeInterval(60)
    coordinator.log(secondBenchSet, as: SetLog(weight: .pounds(195), reps: 6, rpe: .eight))

    #expect(liveActivity.calls.count == 2)
    #expect(liveActivity.invalidationCalls.count == 2)
    #expect(liveActivity.calls[1].content.exerciseName == "DB Row")
    #expect(liveActivity.calls[1].content.restStartDate == Date(timeIntervalSinceReferenceDate: 2_060))
    #expect(liveActivity.calls[1].content.restEndDate == Date(timeIntervalSinceReferenceDate: 2_270))
}

@MainActor
@Test func failedSetLogDoesNotStartLiveActivity() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    logging.error = .failed
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: logging,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: sync,
            restTimer: restTimer,
            restDurations: restDurations(standard: 210),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.isEmpty)
}

@MainActor
@Test func loggingSetFromNonCurrentSessionDoesNotStartLiveActivity() throws {
    let current = makeSingleSetSession(dayNumber: 1)
    let browsed = makeCoordinatorSession()
    browsed.dayNumber = 2
    connectCoordinatorWeek([current.session, browsed])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: browsed,
        wiring: .fixture(
            logging: logging,
            navigation: SpySessionNavigationAdapter(liveEdge: { LiveEdge.resolve(viewedSession: $0, currentSession: current.session) }),
            sync: sync,
            restTimer: restTimer,
            restDurations: restDurations(standard: 210),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(browsed.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.isEmpty)
}

@MainActor
@Test func editSkipAndDeleteDoNotStartLiveActivity() throws {
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    let editLiveActivity = SpySessionLiveActivityAdapter()
    let editFixture = try makeRestActionFixture(liveActivity: editLiveActivity)
    let squatSet = try #require(editFixture.session.exercises.first { $0.order == 0 }?.sets.first)
    editFixture.coordinator.updateLoggedSet(squatSet, as: log)
    #expect(editLiveActivity.calls.isEmpty)
    #expect(editLiveActivity.invalidationCalls.count == 1)

    let skipLiveActivity = SpySessionLiveActivityAdapter()
    let skipFixture = try makeRestActionFixture(liveActivity: skipLiveActivity)
    let skipSet = try #require(skipFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    skipFixture.coordinator.skip(skipSet)
    #expect(skipLiveActivity.calls.isEmpty)
    #expect(skipLiveActivity.invalidationCalls.count == 1)

    let deleteLiveActivity = SpySessionLiveActivityAdapter()
    let deleteFixture = try makeRestActionFixture(liveActivity: deleteLiveActivity)
    let deleteSet = try #require(deleteFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    deleteSet.state = .logged
    deleteSet.setLog = log
    deleteFixture.coordinator.deleteLog(for: deleteSet)
    #expect(deleteLiveActivity.calls.isEmpty)
    #expect(deleteLiveActivity.invalidationCalls.count == 1)
}

@MainActor
@Test func sessionWiringDrivesItsLiveActivityAdapter() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let bound = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: SpySessionSyncAdapter(),
            restTimer: restTimer,
            restDurations: restDurations(standard: 123),
            liveActivity: bound,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(bound.calls.count == 1)
    #expect(bound.calls.first?.sessionLabel == "Week 1 - Day 1")
    #expect(bound.calls.first?.content.exerciseName == "Bench Press")
    #expect(bound.invalidationCalls.count == 1)
}

@MainActor
@Test func loggingAtTheLiveEdgeKeepsTheRestLiveActivityAlive() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let navigation = SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) })
    navigation.liveEdge = .atLiveEdge(currentSession: session)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: navigation,
            sync: SpySessionSyncAdapter(),
            restTimer: restTimer,
            restDurations: restDurations(standard: 123),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.count == 1)
    #expect(liveActivity.invalidationCalls.map(\.isAtLiveEdge) == [true])
}

/// The real stores over the fresh-block workbook, with the coordinator built on the store the app
/// hands it. Only the Live Activity is a spy, so a reconcile is visible.
@MainActor
private func makeStoreDrivenCoordinator() async throws -> (WorkoutApplication, SessionCoordinator, SpySessionLiveActivityAdapter) {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
    let liveActivity = SpySessionLiveActivityAdapter()
    let coordinator = SessionCoordinator(
        session: app.workout.viewedSession,
        wiring: .fixture(logging: app.workout, navigation: app.workout, liveActivity: liveActivity)
    )
    return (app, coordinator, liveActivity)
}

/// A sync replaces every Session model, so the Session the coordinator is bound to is a stale
/// instance whose own live edge reads browsed away while the athlete is still at the live edge.
@MainActor
@Test func aSyncThatReplacesTheBlockReconcilesTheRestLiveActivityAtTheReplacementsLiveEdge() async throws {
    let (app, coordinator, liveActivity) = try await makeStoreDrivenCoordinator()
    let stale = try #require(app.workout.viewedSession)

    _ = try await app.sync()
    await waitUntil(
        { liveActivity.invalidationCalls.count >= 1 },
        orRecord: "Expected 1 reconcile, saw \(liveActivity.invalidationCalls.count)"
    )

    let replacement = try #require(app.workout.currentSession)
    #expect(replacement !== stale)
    #expect(!app.workout.liveEdge(for: stale).isAtLiveEdge)
    #expect(liveActivity.invalidationCalls == [.atLiveEdge(currentSession: replacement)])
}

/// Each Make Current moves the Current Session. Every change in one main-actor turn lands in one
/// reconcile, and the coordinator keeps listening after it.
@MainActor
@Test func eachMakeCurrentReconcilesTheRestLiveActivityAtTheNewCurrentSession() async throws {
    let (app, coordinator, liveActivity) = try await makeStoreDrivenCoordinator()
    defer { withExtendedLifetime(coordinator) {} }

    app.workout.show(SessionAddress(week: 1, day: 2))
    app.workout.makeViewedSessionCurrent()
    await waitUntil(
        { liveActivity.invalidationCalls.count >= 1 },
        orRecord: "Expected 1 reconcile, saw \(liveActivity.invalidationCalls.count)"
    )
    let firstCurrent = try #require(app.workout.currentSession)

    app.workout.show(SessionAddress(week: 2, day: 1))
    app.workout.makeViewedSessionCurrent()
    await waitUntil(
        { liveActivity.invalidationCalls.count >= 2 },
        orRecord: "Expected 2 reconciles, saw \(liveActivity.invalidationCalls.count)"
    )
    let secondCurrent = try #require(app.workout.currentSession)

    #expect(firstCurrent.address == SessionAddress(week: 1, day: 2))
    #expect(secondCurrent.address == SessionAddress(week: 2, day: 1))
    #expect(
        liveActivity.invalidationCalls == [
            .atLiveEdge(currentSession: firstCurrent), .atLiveEdge(currentSession: secondCurrent)
        ]
    )
}

@MainActor
@Test func viewingASessionReseedsFocusAndReconcilesTheRestLiveActivity() throws {
    let first = makeCoordinatorSession()
    let second = makeCoordinatorSession(blockTab: "Block 28")
    let firstBench = try #require(first.exercises.first { $0.order == 1 })
    let liveActivity = SpySessionLiveActivityAdapter()
    let navigation = SpySessionNavigationAdapter()
    navigation.liveEdge = .atLiveEdge(currentSession: second)
    let coordinator = SessionCoordinator(
        session: first,
        wiring: .fixture(navigation: navigation, liveActivity: liveActivity)
    )
    coordinator.focus(on: try #require(firstBench.sets.first { $0.index == 1 }))

    coordinator.view(second)

    #expect(coordinator.sessionCoordinate == second.placement.coordinate)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(liveActivity.invalidationCalls == [.atLiveEdge(currentSession: second)])
}

@MainActor
@Test func loggingWhileBrowsingAwayAsksTheRestLiveActivityToEnd() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: SpySessionNavigationAdapter(liveEdge: { _ in .browsedAway }),
            sync: SpySessionSyncAdapter(),
            restTimer: restTimer,
            restDurations: restDurations(standard: 123),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.isEmpty)
    #expect(liveActivity.invalidationCalls == [.browsedAway])
}
