import Foundation

/// The single representation of a rest interval between Sets: a `start…end` span of a
/// chosen `RestKind`. It owns the rest's timing arithmetic — remaining, elapsed, progress
/// fraction, and the "m:ss" countdown rule — so those are stated once here and shared by every
/// consumer (the pill's presentation, the timer/haptics, and the coordinator's Live Activity
/// range) rather than reconstructed in each caller.
struct RestInterval: Equatable, Sendable {
    let start: Date
    let end: Date
    let kind: RestKind

    init(start: Date, duration: TimeInterval, kind: RestKind) {
        self.start = start
        self.end = start.addingTimeInterval(duration)
        self.kind = kind
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// Seconds left until `end`, clamped to zero at or after `end`. Raw (unrounded) so
    /// `start + remaining(at: start) == end` and progress stays continuous; countdown rounding
    /// lives in `countdownText(at:)`.
    func remaining(at now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    /// Seconds elapsed since `start`, clamped to `0…duration`.
    func elapsed(at now: Date) -> TimeInterval {
        min(duration, max(0, now.timeIntervalSince(start)))
    }

    /// Fraction of the interval still remaining, clamped to `0…1`.
    func progressFraction(at now: Date) -> Double {
        Self.progressFraction(remaining: remaining(at: now), duration: duration)
    }

    /// The one "remaining ÷ duration" rule, clamped to `0…1`, shared by every rest-progress
    /// display. Used both by `progressFraction(at:)` and by the pill's presentation, so the pill's
    /// re-derivation is absorbed here rather than duplicated.
    static func progressFraction(remaining: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining / duration))
    }

    /// "m:ss" countdown for the time remaining, preserving the pill's ceiling behaviour so a
    /// partially-elapsed second still reads as the whole second it is counting down.
    func countdownText(at now: Date) -> String {
        Self.countdownText(seconds: Int(ceil(remaining(at: now))))
    }

    /// The one "seconds → m:ss" rule, shared by every rest-time display.
    static func countdownText(seconds: Int) -> String {
        let minutes = seconds / 60
        let secondsRemainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", secondsRemainder))"
    }
}
