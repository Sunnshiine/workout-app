import CoreGraphics
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

extension QuadraticBezier {
    /// A path's trim runs on length, not on `t`.
    func lengthFraction(at t: CGFloat) -> CGFloat {
        length(to: t) / length(to: 1)
    }

    private func length(to t: CGFloat) -> CGFloat {
        let samples = 200
        var total: CGFloat = 0
        var last = start
        for index in 1...samples {
            let next = point(at: t * CGFloat(index) / CGFloat(samples))
            total += hypot(next.x - last.x, next.y - last.y)
            last = next
        }
        return total
    }
}
