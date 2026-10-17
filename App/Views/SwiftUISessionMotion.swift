import SwiftUI
import UIKit

struct SwiftUISessionMotion: SessionMotionPerforming {
    var reducesMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        guard let animation = motion.animation else {
            return try withTransaction(\.disablesAnimations, true, change)
        }
        try withAnimation(animation, change)
    }
}
