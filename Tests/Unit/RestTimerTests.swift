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
