import Foundation

/// One line of a Warm-up Room Plan: take `kilograms` for `reps` when the platform is `attemptsOut`
/// Attempts from the athlete.
struct WarmupRoomStep: Hashable, Codable, Sendable {
    var kilograms: Kilograms
    var reps: Int
    var attemptsOut: Int
}

/// Every wait is whole Attempts, and seconds are those Attempts at the athlete's Seconds per Attempt,
/// an estimate no rulebook states.
enum MeetCue: Equatable, Sendable {
    case warmUp(WarmupRoomStep, attemptsUntil: Int, secondsUntil: Int)
    /// The Warm-up Room Plan is done, or this Attempt has none. The athlete waits for the platform.
    case attempt(Kilograms, attemptsOut: Int, secondsUntil: Int)
    case platform(Kilograms)
}

/// It holds no clock, so every transition is a value a test can name.
enum MeetClock {
    static func cue(attemptsOut: Int, secondsPerAttempt: Int, warmups: [WarmupRoomStep], attempt: Kilograms) -> MeetCue {
        guard attemptsOut > 0 else { return .platform(attempt) }
        let next = warmups.filter { $0.attemptsOut <= attemptsOut }.max { $0.attemptsOut < $1.attemptsOut }
        guard let next else {
            return .attempt(attempt, attemptsOut: attemptsOut, secondsUntil: attemptsOut * secondsPerAttempt)
        }
        let attemptsUntil = attemptsOut - next.attemptsOut
        return .warmUp(next, attemptsUntil: attemptsUntil, secondsUntil: attemptsUntil * secondsPerAttempt)
    }
}

/// It keeps its start, the tap that marked the Attempt before it, so a relaunch reads the true time
/// left.
struct AttemptWindow: Hashable, Codable, Sendable {
    let lift: MainLift
    let startedAt: Date
    let seconds: Int

    /// When the table's rule starts to show. Only the last quarter of the minute reads as closing,
    /// so the rule arrives when it matters and the first 45 seconds stay calm.
    static let closingSeconds = 15

    enum Reading: Equatable, Sendable {
        case open(secondsLeft: Int)
        case closing(secondsLeft: Int)
        case expired
    }

    func reading(at now: Date) -> Reading {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt).rounded(.down)))
        let left = seconds - elapsed
        if left <= 0 { return .expired }
        return left <= Self.closingSeconds ? .closing(secondsLeft: left) : .open(secondsLeft: left)
    }
}
