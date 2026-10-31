import Foundation

@testable import WorkoutTracker

/// Holds the one wake an Effort Countdown asked for, and rings it when a test moves time past it.
@MainActor
final class SteppedCountdownTime: RestExpiryScheduling {
    let clock: ManualRestClock
    private(set) var deadline: Date?
    private var expire: (@MainActor () -> Void)?

    init(clock: ManualRestClock) {
        self.clock = clock
    }

    func schedule(deadline: Date, expire: @escaping @MainActor () -> Void) {
        self.deadline = deadline
        self.expire = expire
    }

    func cancel() {
        deadline = nil
        expire = nil
    }

    /// Moves the clock `seconds` on, ringing each wake on its way at the instant it asked for.
    func advance(by seconds: TimeInterval) {
        let target = clock.now.addingTimeInterval(seconds)
        while let deadline, deadline <= target {
            clock.now = deadline
            ring()
        }
        clock.now = target
    }

    /// Rings the wake now, whether or not its instant has come, as a timer that fires early or
    /// twice would.
    func ring() {
        let expire = expire
        self.deadline = nil
        self.expire = nil
        expire?()
    }
}

/// Every cue a countdown played, at the second from the start it played, and each silence.
@MainActor
final class RecordingCountdownCues: CountdownCuePlaying {
    private let clock: ManualRestClock
    private let start: Date
    private(set) var played: [(second: TimeInterval, cue: CountdownCue)] = []
    private(set) var silences = 0

    init(clock: ManualRestClock) {
        self.clock = clock
        self.start = clock.now
    }

    var spoken: [String] { played.map(\.cue.spokenText) }
    var seconds: [TimeInterval] { played.map(\.second) }

    func play(_ cue: CountdownCue) {
        played.append((clock.now.timeIntervalSince(start), cue))
    }

    func silence() {
        silences += 1
    }
}
