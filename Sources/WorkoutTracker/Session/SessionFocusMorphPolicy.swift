import Foundation

enum SessionFocusMorphAction: Equatable, Sendable {
    case pendingFocus
    case loggedReviewOpen
    case loggedReviewCollapse
    case supersetSwitchSucceeded
}

struct SessionFocusMorphPolicy: Equatable, Sendable {
    let reduceMotion: Bool

    func shouldAnimate(_ action: SessionFocusMorphAction) -> Bool {
        guard !reduceMotion else { return false }

        return switch action {
        case .pendingFocus, .loggedReviewOpen, .supersetSwitchSucceeded:
            true
        case .loggedReviewCollapse:
            false
        }
    }
}
