import SwiftUI

/// The transaction a coordinator verb runs its change in. The coordinator picks it; the App's
/// performer only wraps the change in the matching animation.
enum SessionMotion: Equatable, Sendable {
    case momentumFlow
    case skipFadeUp
    case focusMorph

    func runs(reducingMotion: Bool) -> Bool {
        switch self {
        case .momentumFlow, .skipFadeUp: true
        case .focusMorph: !reducingMotion
        }
    }

    var animation: Animation {
        switch self {
        case .momentumFlow: Theme.momentumFlowAnimation
        case .skipFadeUp: Theme.skipFadeUpAnimation
        case .focusMorph: Theme.focusMorphAnimation
        }
    }
}

@MainActor
protocol SessionMotionPerforming {
    var reducesMotion: Bool { get }
    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows
}

/// What a coordinator with no screen bound performs: every change lands at once.
struct ImmediateSessionMotion: SessionMotionPerforming {
    var reducesMotion: Bool { false }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        try change()
    }
}
