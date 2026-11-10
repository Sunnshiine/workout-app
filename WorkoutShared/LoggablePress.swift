import Foundation

/// How the Lock Screen card logs the Set it shows.
enum LoggablePress: Codable, Hashable, Sendable {
    case ready(Offer)
    /// Nothing to tap but the mic and the app.
    case needsApp

    // Opens the app where it was. No request is attached, so nothing starts listening.
    // swiftlint:disable:next force_unwrapping
    static let appURL = URL(string: "workouttracker://")!

    /// The Reps and the RPE the card offers. `setIdentity` goes back to the app with each press,
    /// which finds the Set by it and refuses when the card has moved on.
    struct Offer: Codable, Hashable, Sendable {
        let repChoices: [Int]
        /// The choices inside the Prescribed Reps, which carry the tick.
        let prescribedReps: [Int]
        let rpeChoices: [String]
        /// The coach's RPE, which carries the tick. Nil unless the Load cell names one point.
        let prescribedRPE: String?
        let setIdentity: String
    }
}

/// The Start the card shows in the mic's place for a Set that opens on a timed effort. It opens
/// the app, where the Set's card counts the effort as a tap on its own control does.
struct LockScreenStartOffer: Codable, Hashable, Sendable {
    /// What the stage's control reads, as `10 s hold`.
    let label: String
    /// As VoiceOver reads it, `10 second hold`.
    let spokenLabel: String
    let url: URL
}
