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
        progressFraction = RestInterval.progressFraction(remaining: clampedRemaining, duration: duration)
        accessibilityLabel = Self.accessibilityLabel(kind: kind, minutes: minutes, seconds: seconds)
    }

    private static func accessibilityLabel(kind: RestKind, minutes: Int, seconds: Int) -> String {
        let units = [spokenUnit(minutes, "minute"), spokenUnit(seconds, "second")].compactMap { $0 }
        // An expired interval drops both units, and VoiceOver still announces a duration.
        let duration = units.isEmpty ? "0 seconds" : units.joined(separator: " ")
        return "\(kind.label), \(duration) remaining"
    }

    /// One pluralized time unit as VoiceOver speaks it, or nil when the unit is zero and drops out
    /// of the spoken duration.
    private static func spokenUnit(_ count: Int, _ unit: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
