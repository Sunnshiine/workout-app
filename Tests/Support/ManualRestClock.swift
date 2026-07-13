import Foundation

@testable import WorkoutTracker

/// Hand-advanced `RestClock` for deterministic rest-timing tests: `now` moves only when a test
/// calls `advance(by:)`, never on the wall clock. Shared so the rest-timer and haptic-emission
/// suites use one clock double instead of copies.
@MainActor
final class ManualRestClock: RestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }
}
