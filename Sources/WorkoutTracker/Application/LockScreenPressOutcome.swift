import Foundation

extension LockScreenPress {
    enum Outcome: Equatable, Sendable {
        case logged(SetLog, at: ActiveSetID)
        /// The same chip again, as a chalky double tap presses it: the Set already holds this Set
        /// Log, so nothing changes and the next Set's card stays.
        case sameSetLog(at: ActiveSetID)
        /// The face the card is on after the press, which is its rest face when the Set has no
        /// such face or no card is up. Nothing was written.
        case turned(to: LockScreenFace)
        case notLogged(NotLogged)
    }

    /// Wrote nothing, and the Live Activity says why.
    enum NotLogged: Equatable, Sendable {
        /// The press carries a Set, Reps, or an RPE this build cannot read.
        case unreadable
        case noCurrentSession
        case sessionChanged
        /// The Set took another Set Log, or a skip, since the card drew. `setLog` reads it back.
        case setSettled(setLog: String?, set: LiveActivityDictationContent.WrittenSet)
        /// The card now offers another Set, or the Sheet no longer holds this one.
        case cardMovedOn
        /// The stage's card holds another weight than the one the Lock Screen showed.
        case cardChanged
        case writeFailed
        /// An RPE tap as the card turned to RPE, which the second tap of a double tap on a Reps Chip
        /// makes. The card that follows the readback still offers RPE for the same Reps.
        case tooSoonAfterReps
        /// A mic press is in flight, so the Set is the mic's: the Lock Screen's, or the card's in
        /// the app.
        case micBusy(SetDictation.Surface)
    }
}
