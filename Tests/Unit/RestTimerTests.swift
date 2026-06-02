import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private final class ManualRestClock: RestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }
}

@MainActor
@Test func restTimerStartSetsDeadlineAndRemainingTracksClock() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(timer.deadline == Date(timeIntervalSinceReferenceDate: 1_120))
    #expect(timer.remaining == 120)
    #expect(timer.isRunning)

    clock.advance(by: 45)

    #expect(timer.remaining == 75)
    #expect(timer.isRunning)

    clock.advance(by: 75)

    #expect(timer.remaining == 0)
    #expect(!timer.isRunning)
}

@MainActor
@Test func restTimerDismissClearsActiveRest() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    timer.dismiss()

    #expect(timer.deadline == nil)
    #expect(timer.remaining == 0)
    #expect(!timer.isRunning)
}

@MainActor
@Test func restTimerRestartReplacesDeadlineOriginAndAdvancesRestartRevision() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    clock.advance(by: 30)
    timer.start(duration: 180, origin: ActiveSetID(exerciseOrder: 2, setIndex: 1))

    #expect(timer.deadline == Date(timeIntervalSinceReferenceDate: 1_210))
    #expect(timer.remaining == 180)
    #expect(timer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 1))
    #expect(timer.restartRevision == 2)
}

@MainActor
@Test func restTimerCancelsOnlyMatchingOrigin() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)
    let origin = ActiveSetID(exerciseOrder: 1, setIndex: 0)

    timer.start(duration: 120, origin: origin)
    timer.cancel(ifOriginMatches: ActiveSetID(exerciseOrder: 1, setIndex: 1))

    #expect(timer.isRunning)
    #expect(timer.origin == origin)

    timer.cancel(ifOriginMatches: origin)

    #expect(timer.deadline == nil)
    #expect(timer.origin == nil)
    #expect(!timer.isRunning)
}
