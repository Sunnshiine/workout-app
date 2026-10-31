import Foundation

extension TimedEffort {
    /// The card's control: `10 s hold`, `40 s`, `1:30 hold`, `25 min`.
    var controlLabel: String {
        switch self {
        case .openingHold(let duration): "\(duration.shortLabel) hold"
        case .timedSet(let duration): duration.shortLabel
        }
    }

    /// The control as VoiceOver reads it: `10 second hold`, `40 second Set`.
    var spokenLabel: String {
        switch self {
        case .openingHold(let duration): "\(duration.spokenLabel) hold"
        case .timedSet(let duration): "\(duration.spokenLabel) Set"
        }
    }
}

extension EffortDuration {
    /// `10 s`, `2 min`, `1:30`.
    fileprivate var shortLabel: String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds.isMultiple(of: 60) { return "\(seconds / 60) min" }
        return Self.clock(seconds)
    }

    /// `10 second`, `2 minute`, `90 second`, as an adjective before hold or Set.
    fileprivate var spokenLabel: String {
        seconds >= 60 && seconds.isMultiple(of: 60) ? "\(seconds / 60) minute" : "\(seconds) second"
    }

    /// `1:30`, `0:45`.
    fileprivate static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// What the card's face shows of an Effort Countdown at one instant.
struct EffortCountdownFace: Equatable {
    /// `Get set` through the Lead-in, `Hold` or `Go` through the effort, `Done` or `Time` after.
    let caption: String
    /// The Lead-in's seconds, then the effort's seconds left, with minutes as `1:30`.
    let numeral: String
    /// The share of the effort gone, stepping once a second: 0 through the Lead-in, 1 once done.
    let progress: Double
    /// `Tap to stop` while it counts, `Tap to close` through the finished linger.
    let hint: String
    let accessibilityValue: String

    init(_ run: CountdownRun, at now: Date) {
        let begins = CountdownCue.begins(run.effort).spokenText
        switch run.phase(at: now) {
        case .leadIn(let secondsLeft):
            caption = "Get set"
            numeral = "\(secondsLeft)"
            progress = 0
            hint = "Tap to stop"
            accessibilityValue = "Starts in \(secondsLeft)"
        case .effort(let secondsLeft, let elapsedFraction):
            caption = begins
            numeral = secondsLeft < 60 ? "\(secondsLeft)" : EffortDuration.clock(secondsLeft)
            progress = elapsedFraction
            hint = "Tap to stop"
            accessibilityValue = "\(begins), \(secondsLeft) \(secondsLeft == 1 ? "second" : "seconds") left"
        case .finished:
            caption = CountdownCue.ends(run.effort).spokenText
            numeral = "0"
            progress = 1
            hint = "Tap to close"
            accessibilityValue = caption
        }
    }
}
