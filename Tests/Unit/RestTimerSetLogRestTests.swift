import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func aSetLogsRestRunsForItsKindAndOnlyThatSetsCancelEndsIt() throws {
    let (session, bench) = makeBenchSession(states: [.logged, .pending])
    let logged = bench.sets[0]
    let timer = RestTimer(clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000)))

    let started = timer.startRest(
        afterLogging: logged,
        in: session,
        wasSupersetMember: true,
        durations: restDurations(standard: 180, superset: 90)
    )

    #expect(started)
    #expect(timer.interval == RestInterval(start: Date(timeIntervalSinceReferenceDate: 1_000), duration: 90, kind: .superset))

    timer.cancelRest(startedBy: bench.sets[1])
    #expect(timer.isRunning)

    timer.cancelRest(startedBy: logged)
    #expect(timer.interval == nil)
}

@MainActor
@Test func aSetLogThatClearsTheWeekStartsNoRest() {
    let (session, bench) = makeBenchSession(states: [.logged])
    let timer = RestTimer(clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000)))

    let started = timer.startRest(afterLogging: bench.sets[0], in: session, wasSupersetMember: false, durations: restDurations())

    #expect(!started)
    #expect(timer.interval == nil)
}

@MainActor
private func makeBenchSession(states: [SetState]) -> (Session, Exercise) {
    let bench = Exercise(name: "Bench Press", coachNote: nil, order: 1)
    bench.sets = states.enumerated().map { index, state in
        ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: state)
    }
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = [bench]
    Week(number: 1).sessions = [session]
    return (session, bench)
}
