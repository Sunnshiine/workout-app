import CoreGraphics
import Foundation

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
        stemTrim = Theme.wingEase.progress(at: elapsed / Theme.Motion.ceremonyStem)
        birdLanding = Theme.wingEase.progress(at: (elapsed - birdStart) / Theme.Motion.ceremonyBird)
    }

    /// A leaf's ink, 0...1, once the drawn stem passes its place along the stem's length.
    func leafInk(atLengthFraction position: Double) -> Double {
        min(max((stemTrim - position) / 0.08, 0), 1)
    }
}

extension Theme.BezierEase {
    /// The eased progress at linear time `x`, so one clock can carry the ease on each of its spans.
    func progress(at x: Double) -> Double {
        // The clamps return exact end values, so a finished span draws today's pixels.
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var low = 0.0
        var high = 1.0
        for _ in 0..<50 {
            let mid = (low + high) / 2
            if Self.coordinate(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return Self.coordinate((low + high) / 2, y1, y2)
    }

    private static func coordinate(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
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
