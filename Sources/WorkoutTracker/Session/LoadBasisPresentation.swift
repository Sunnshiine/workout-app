import Foundation

struct LoadBasisPresentation: Equatable, Sendable {
    let text: String

    @MainActor
    init(_ basis: LoadBasis, for set: ExerciseSet) {
        switch basis.origin {
        case .today(let setIndex):
            text = "from Set \(setIndex + 1) today"
        case .history(let session, let baseName):
            let sessionLabel = session.address.sessionLabel
            let place =
                session.blockTab == set.exercise?.session?.week?.block?.tabName
                ? sessionLabel : "\(session.blockTab) \(sessionLabel)"
            let matchedName = baseName.lowercased() == set.exercise?.baseName.lowercased() ? "" : " as “\(baseName)”"
            text = "from \(basis.setLog.formatted) · \(place)\(matchedName)"
        }
    }
}
