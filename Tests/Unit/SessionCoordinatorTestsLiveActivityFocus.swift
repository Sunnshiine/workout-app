import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func makeFocusedRestFixture() throws -> (
    session: Session,
    coordinator: SessionCoordinator,
    liveActivity: SpySessionLiveActivityAdapter,
    clock: ManualCoordinatorRestClock
) {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: SpySessionNavigationAdapter(current: session),
            sync: SpySessionSyncAdapter(),
            restTimer: RestTimer(clock: clock),
            restDurations: restDurations(standard: 210),
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    coordinator.log(try #require(bench.sets.first { $0.index == 0 }), as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    return (session, coordinator, liveActivity, clock)
}

@MainActor
@Test func loggingAtTheCurrentSessionPointsTheLiveActivityAtTheNextActiveSetOnce() throws {
    let fixture = try makeFocusedRestFixture()

    #expect(fixture.liveActivity.calls.map(\.content.exerciseName) == ["Bench Press"])
    #expect(fixture.liveActivity.retargets.isEmpty)
}

@MainActor
@Test func focusingAnotherExerciseDuringRestRetargetsTheLiveActivityAtItsRest() throws {
    let fixture = try makeFocusedRestFixture()
    let row = try #require(fixture.session.exercises.first { $0.order == 2 })

    fixture.coordinator.focus(on: try #require(row.sets.first))

    let retarget = try #require(fixture.liveActivity.retargets.last)
    #expect(fixture.liveActivity.retargets.count == 1)
    #expect(retarget.exerciseName == "DB Row")
    #expect(retarget.prescribedReps == "10")
    #expect(retarget.setsDone == 0)
    #expect(retarget.setsTotal == 1)
    #expect(
        retarget.target
            == LiveActivityRestTarget(
                session: try #require(fixture.session.placement.coordinate),
                setID: ActiveSetID(exerciseOrder: 2, setIndex: 0)
            )
    )
    #expect(retarget.restStartDate == Date(timeIntervalSinceReferenceDate: 2_000))
    #expect(retarget.restEndDate == Date(timeIntervalSinceReferenceDate: 2_210))
    #expect(fixture.liveActivity.calls.count == 1)
}

@MainActor
@Test func jumpingToAnotherExerciseAfterRestEndsRetargetsTheReadyLiveActivity() throws {
    let fixture = try makeFocusedRestFixture()
    let row = try #require(fixture.session.exercises.first { $0.order == 2 })
    fixture.clock.now.addTimeInterval(600)

    fixture.coordinator.jump(to: try #require(row.sets.first))

    let retarget = try #require(fixture.liveActivity.retargets.last)
    #expect(retarget.exerciseName == "DB Row")
    #expect(retarget.restEndDate == Date(timeIntervalSinceReferenceDate: 2_210))
}

@MainActor
@Test func focusingAnotherExerciseAfterTheLiveActivityEndedLeavesItEnded() throws {
    let fixture = try makeFocusedRestFixture()
    let row = try #require(fixture.session.exercises.first { $0.order == 2 })
    fixture.coordinator.cancelRestForSessionExit()

    fixture.coordinator.focus(on: try #require(row.sets.first))

    #expect(fixture.liveActivity.retargets.isEmpty)
}
