import Foundation
import SwiftUI

struct MoveOnCeremonyFrame: Equatable {
    static let duration = Theme.Motion.ceremonyStem + Theme.Motion.ceremonyBeat + Theme.Motion.ceremonyBird

    let stemTrim: Double
    let birdLanding: Double

    init(elapsed: TimeInterval) {
        let birdStart = Theme.Motion.ceremonyStem + Theme.Motion.ceremonyBeat
        stemTrim = max(0, Self.wing.value(at: elapsed / Theme.Motion.ceremonyStem))
        birdLanding = max(0, Self.wing.value(at: (elapsed - birdStart) / Theme.Motion.ceremonyBird))
    }

    private static let wing = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: Theme.wingEase.x1, y: Theme.wingEase.y1),
        endControlPoint: UnitPoint(x: Theme.wingEase.x2, y: Theme.wingEase.y2)
    )

    private static let inkSpan = 0.08

    func leafInk(atLengthFraction position: Double) -> Double {
        guard stemTrim < 1 else { return 1 }
        return min(max((stemTrim - position) / Self.inkSpan, 0), 1)
    }
}
