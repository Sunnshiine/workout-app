import Foundation

enum SessionFocusMorphAction: Equatable, Sendable {
    case pendingFocus
    case loggedReviewOpen
    case loggedReviewCollapse
}

struct SessionFocusMorphPolicy: Equatable, Sendable {
    let reduceMotion: Bool

    func shouldAnimate(_ action: SessionFocusMorphAction) -> Bool {
        guard !reduceMotion else { return false }

        return switch action {
        case .pendingFocus, .loggedReviewOpen:
            true
        case .loggedReviewCollapse:
            false
        }
    }
}
