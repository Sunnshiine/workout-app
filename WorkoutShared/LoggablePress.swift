import Foundation

/// How the Lock Screen card logs the Set it shows.
enum LoggablePress: Codable, Hashable, Sendable {
    case ready(Offer)
    /// No chips, only the mic and the app.
    case needsApp

    /// Reps Chips, then RPE Chips. A Reps tap turns the row and writes nothing, and an RPE tap logs
    /// the weight the card shows at the Reps and the RPE tapped. `setIdentity` goes back to the app
    /// with each press, which finds the Set by it and refuses when the card has moved on.
    struct Offer: Codable, Hashable, Sendable {
        let repChoices: [Int]
        /// The choices inside the Prescribed Reps, which carry the tick.
        let prescribedReps: [Int]
        let rpeChoices: [String]
        /// The coach's RPE, which carries the tick. Nil unless the Load cell names one point.
        let prescribedRPE: String?
        let setIdentity: String
        /// The Reps the athlete tapped, which turned the row to RPE. Nil while it offers Reps.
        let chosenReps: Int?
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
