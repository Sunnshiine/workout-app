import Foundation

/// What the back control reads while a Session other than the current one is open.
struct OffLiveEdgePresentation {
    let backLabel: String

    @MainActor
    init(currentSession: Session?) {
        guard let currentSession else {
            backLabel = "Back"
            return
        }
        if let address = currentSession.address {
            backLabel = "Back to \(address.sessionLabel)"
        } else {
            backLabel = "Back to Day \(currentSession.dayNumber)"
        }
    }
}
