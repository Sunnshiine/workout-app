import Foundation

/// The line that names a Load Basis, for the Set card and the `workout` CLI alike: `from Set 1 today`,
/// `from 315x5@7 · W1 D2` within the Set's own Block, `from 195x5@8 · Block 26 W4 D1` across Blocks.
/// It never begins with `Block `, which is how the Last Performed line reads.
struct LoadBasisPresentation: Equatable, Sendable {
    let text: String

    @MainActor
    init(_ basis: LoadBasis, for set: ExerciseSet) {
        switch basis.origin {
        case .today(let setIndex):
            text = "from Set \(setIndex + 1) today"
        case .history(let session):
            let sessionLabel = session.address.sessionLabel
            let place =
                session.blockTab == set.exercise?.session?.week?.block?.tabName
                ? sessionLabel : "\(session.blockTab) \(sessionLabel)"
            text = "from \(basis.setLog.formatted) · \(place)"
        }
    }
}
