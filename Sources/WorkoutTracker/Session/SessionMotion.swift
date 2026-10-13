import SwiftUI

enum SessionMotion: Equatable, Sendable {
    case momentumFlow
    case skipFadeUp
    case focusMorph
    /// The change lands in one frame, with the views' own implicit animations switched off too.
    case cut

    func runs(reducingMotion: Bool) -> Bool {
        switch self {
        case .momentumFlow, .skipFadeUp, .cut: true
        case .focusMorph: !reducingMotion
        }
    }

    var animation: Animation? {
        switch self {
        case .momentumFlow: Theme.momentumFlowAnimation
        case .skipFadeUp: Theme.skipFadeUpAnimation
        case .focusMorph: Theme.focusMorphAnimation
        case .cut: nil
        }
    }
}

@MainActor
protocol SessionMotionPerforming {
    var reducesMotion: Bool { get }
    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows
}

struct ImmediateSessionMotion: SessionMotionPerforming {
    var reducesMotion: Bool { false }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        try change()
    }
}
