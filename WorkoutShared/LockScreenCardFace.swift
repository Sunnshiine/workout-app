import Foundation

/// Which Card Face the Lock Screen card draws. The app decides it and the card only draws it, so
/// each of the card's controls names the face it turns to.
enum LockScreenCardFace: Codable, Hashable, Sendable {
    case rest
    case coachNote
    case reps
    /// The RPE choices for the Reps the athlete tapped.
    case rpe(reps: Int)

    /// As an intent's parameter carries the face, since App Intents take no enum with a payload.
    var token: String {
        switch self {
        case .rest: "rest"
        case .coachNote: "coachNote"
        case .reps: "reps"
        case .rpe(let reps): "rpe \(reps)"
        }
    }

    init?(token: String) {
        switch token {
        case "rest": self = .rest
        case "coachNote": self = .coachNote
        case "reps": self = .reps
        default:
            guard token.hasPrefix("rpe "), let reps = Int(token.dropFirst(4)) else { return nil }
            self = .rpe(reps: reps)
        }
    }
}

/// One of the three numbers on the card's rest face, as the app worded it.
struct LockScreenCardStat: Codable, Hashable, Sendable {
    /// The unit over the value, as `LBS`. Empty over a value that names itself, as `BW` does.
    let label: String
    let value: String
    /// As VoiceOver reads the pair.
    let spoken: String
    /// True where the Set has no such value, which draws its dash muted.
    let isMissing: Bool
}
