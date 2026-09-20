import Foundation

@MainActor
enum LiveEdge: Equatable {
    case atLiveEdge(currentSession: Session)
    case browsedAway

    static func resolve(viewedSession: Session?, currentSession: Session?) -> LiveEdge {
        guard
            let viewedSession,
            let currentSession,
            viewedSession.persistentModelID == currentSession.persistentModelID
        else {
            return .browsedAway
        }
        return .atLiveEdge(currentSession: currentSession)
    }

    var isAtLiveEdge: Bool {
        switch self {
        case .atLiveEdge: true
        case .browsedAway: false
        }
    }
}
