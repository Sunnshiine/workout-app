import Foundation

struct RestPillPresentation: Equatable, Sendable {
    let visibleTypeLabel: String?
    let countdownText: String
    let accessibilityLabel: String
    let progressFraction: Double

    init(kind: RestKind, remaining: TimeInterval, duration: TimeInterval) {
        let clampedRemaining = max(0, remaining)
        let totalSeconds = Int(ceil(clampedRemaining))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        visibleTypeLabel = nil
        countdownText = RestInterval.countdownText(seconds: totalSeconds)
        progressFraction = Self.progressFraction(remaining: clampedRemaining, duration: duration)
        accessibilityLabel = Self.accessibilityLabel(kind: kind, minutes: minutes, seconds: seconds)
    }

    private static func progressFraction(remaining: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining / duration))
    }

    private static func accessibilityLabel(kind: RestKind, minutes: Int, seconds: Int) -> String {
        if minutes > 0, seconds > 0 {
            return "\(kind.label), \(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s") remaining"
        }
        if minutes > 0 {
            return "\(kind.label), \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        }
        return "\(kind.label), \(seconds) second\(seconds == 1 ? "" : "s") remaining"
    }
}
