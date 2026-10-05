import CoreGraphics
import Foundation
import SwiftUI

/// The Move On ceremony at one instant of its growth (DESIGN.md §5.7, §7): the stem draws on the
/// wing, each leaf inks as the stem passes it, a beat, then the songbird drops onto the tip.
struct MoveOnCeremonyFrame: Equatable {
    static let duration = Theme.Motion.ceremonyStem + Theme.Motion.ceremonyBeat + Theme.Motion.ceremonyBird

    /// How much of the stem's length is drawn, 0...1.
    let stemTrim: Double
    /// 0 is clear and lifted off the perch, 1 is landed.
    let birdLanding: Double

    init(elapsed: TimeInterval) {
        let birdStart = Theme.Motion.ceremonyStem + Theme.Motion.ceremonyBeat
        stemTrim = Self.wing.value(at: elapsed / Theme.Motion.ceremonyStem)
        birdLanding = Self.wing.value(at: (elapsed - birdStart) / Theme.Motion.ceremonyBird)
    }

    /// The wing ease on a linear clock. It clamps outside 0...1, so a finished span draws today's
    /// pixels.
    private static let wing = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: Theme.wingEase.x1, y: Theme.wingEase.y1),
        endControlPoint: UnitPoint(x: Theme.wingEase.x2, y: Theme.wingEase.y2)
    )

    /// A leaf's ink, 0...1, once the drawn stem passes its place along the stem's length.
    func leafInk(atLengthFraction position: Double) -> Double {
        min(max((stemTrim - position) / 0.08, 0), 1)
    }
}

extension QuadraticBezier {
    /// The share of the curve's length that lies before parameter `t`. A path's trim runs on
    /// length, not on `t`.
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
