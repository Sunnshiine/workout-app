import Foundation

/// When the Lock Screen card last turned to its RPE face, kept across presses for the app's life.
@MainActor
final class RPEFaceSettle {
    /// A press can land seconds after its tap, so a second tap on a Reps Chip can reach the RPE Chip
    /// that took its place. An RPE press this soon after the card turned writes nothing.
    nonisolated static let duration: Duration = .seconds(1)

    private var rpeFaceShownAt: Duration?

    init() {}

    func rpeFaceShown(at now: Duration) {
        rpeFaceShownAt = now
    }

    func admitsRPEPress(at now: Duration) -> Bool {
        guard let shownAt = rpeFaceShownAt else { return true }
        return now - shownAt >= Self.duration
    }
}
