import Foundation

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
