import SwiftUI

// Throwaway lab for the #452 device feel pass. Geometry and the day palette are
// ported from the locked HTML prototypes (#413 session stage, #414 Sunbird moments)
// so motion is judged in the drawing language the verdicts were made in. The system
// serif design stands in for Fraunces — type is not under test here.

enum MotionLabInk {
    static let paperTop = labColor(0xE8EDDB)
    static let paperBottom = labColor(0xC7E0BF)
    static let ink = labColor(0x152118)
    static let muted = labColor(0x526457)
    static let action = labColor(0x0D6B40)
    static let cream = labColor(0xF2F7E8)
    static let stem = labColor(0x0D6B40)
    static let leafFill = labColor(0x0D6B40)
    static let leafRib = labColor(0xF2F7E8, 0.5)
    static let budFill = labColor(0xF2F7E8, 0.95)
    static let budStroke = labColor(0x0D6B40)
    static let budRib = labColor(0x0D6B40, 0.55)
    static let futureStroke = labColor(0x0D6B40, 0.40)
    static let skipStroke = labColor(0x526457, 0.42)
    static let birdFill = labColor(0x0D6B40)
    static let birdRib = labColor(0xF2F7E8, 0.5)

    static func labColor(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The wing ease — cubic-bezier(0.46, -0.09, 0.83, 0.32), the app's signature timing (#412/#421).
/// Solved numerically so the same curve drives multi-phase choreography from one clock.
enum WingEase {
    static func eased(_ fraction: Double) -> Double {
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return 1 }
        return bezierY(solveT(for: fraction))
    }

    /// Linear 0…1 progress of `elapsed` through a phase window.
    static func phase(_ elapsed: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return elapsed >= start ? 1 : 0 }
        return min(max((elapsed - start) / duration, 0), 1)
    }

    /// The time fraction at which the eased curve first reaches `value` on its rise.
    static func inverseEased(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        guard value < 1 else { return 1 }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if eased(mid) < value { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    private static let x1 = 0.46
    private static let y1 = -0.09
    private static let x2 = 0.83
    private static let y2 = 0.32

    private static func bezierX(_ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t
    }

    private static func bezierY(_ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
    }

    private static func bezierXSlope(_ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
    }

    private static func solveT(for x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = bezierX(t) - x
            guard abs(error) > 0.000_01 else { break }
            let slope = bezierXSlope(t)
            guard abs(slope) > 0.000_001 else { break }
            t = min(max(t - error / slope, 0), 1)
        }
        return t
    }
}

/// A branch stem — one cubic curve with an arc-length table so leaves land at the
/// same fractions the HTML prototypes used (`getPointAtLength` equivalence).
struct MotionLabStem {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint

    private let samples: [CGPoint]
    private let cumulative: [CGFloat]

    init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end

        var points: [CGPoint] = []
        points.reserveCapacity(241)
        for i in 0...240 {
            points.append(Self.evaluate(CGFloat(i) / 240, start, control1, control2, end))
        }
        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(241)
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            lengths.append(lengths[i - 1] + (dx * dx + dy * dy).squareRoot())
        }
        samples = points
        cumulative = lengths
    }

    // the locked stage branch (#413): viewBox 329×148
    static let stage = MotionLabStem(
        start: CGPoint(x: 8, y: 132),
        control1: CGPoint(x: 80, y: 120),
        control2: CGPoint(x: 172, y: 84),
        end: CGPoint(x: 314, y: 22)
    )

    // the locked ceremony branch (#414): viewBox 321×232, bird at the tip
    static let ceremony = MotionLabStem(
        start: CGPoint(x: 22, y: 224),
        control1: CGPoint(x: 36, y: 160),
        control2: CGPoint(x: 92, y: 90),
        end: CGPoint(x: 292, y: 22)
    )

    var path: Path {
        var p = Path()
        p.move(to: start)
        p.addCurve(to: end, control1: control1, control2: control2)
        return p
    }

    func point(atFraction fraction: CGFloat) -> CGPoint {
        guard let total = cumulative.last, total > 0 else { return start }
        let target = min(max(fraction, 0), 1) * total
        var lo = 0
        var hi = cumulative.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < target { lo = mid } else { hi = mid }
        }
        let span = cumulative[hi] - cumulative[lo]
        let within = span > 0 ? (target - cumulative[lo]) / span : 0
        let a = samples[lo]
        let b = samples[hi]
        return CGPoint(x: a.x + (b.x - a.x) * within, y: a.y + (b.y - a.y) * within)
    }

    func angleDegrees(atFraction fraction: CGFloat) -> CGFloat {
        let p = point(atFraction: fraction)
        let q = point(atFraction: min(1, fraction + 0.01))
        guard q != p else { return 0 }
        return atan2(q.y - p.y, q.x - p.x) * 180 / .pi
    }

    private static func evaluate(
        _ t: CGFloat,
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint
    ) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
        let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
        return CGPoint(x: x, y: y)
    }
}

enum MotionLabSetState {
    case logged
    case skipped
    case current
    case future
}

struct MotionLabSetNode: Identifiable {
    let id: Int
    let t: CGFloat
    let scale: CGFloat
    let spread: CGFloat
    var state: MotionLabSetState

    var side: CGFloat { id.isMultiple(of: 2) ? -1 : 1 }

    // the locked five-Set stage layout (#413): two logged, Set 3 current
    static var fiveSetStage: [MotionLabSetNode] {
        [
            MotionLabSetNode(id: 0, t: 0.10, scale: 0.78, spread: 46, state: .logged),
            MotionLabSetNode(id: 1, t: 0.32, scale: 0.68, spread: 52, state: .logged),
            MotionLabSetNode(id: 2, t: 0.56, scale: 0.52, spread: 34, state: .current),
            MotionLabSetNode(id: 3, t: 0.78, scale: 0.30, spread: 24, state: .future),
            MotionLabSetNode(id: 4, t: 0.91, scale: 0.22, spread: 20, state: .future)
        ]
    }

    // the ceremony's fourteen logged Sets tapering toward the tip (#414)
    static var fourteenCeremony: [MotionLabSetNode] {
        (0..<14).map { i in
            MotionLabSetNode(
                id: i,
                t: 0.05 + 0.835 * CGFloat(i) / 13,
                scale: 0.72 - 0.32 * CGFloat(i) / 13,
                spread: 44 + CGFloat(i % 3) * 4,
                state: .logged
            )
        }
    }
}

struct MotionLabStageVariant: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let inkDuration: Double
    /// Bud-open start, measured from the moment the leaf starts inking.
    let budDelay: Double
    let budDuration: Double
    let budOvershoot: Bool

    var total: Double { max(inkDuration, budDelay + budDuration) }

    static let all: [MotionLabStageVariant] = [
        MotionLabStageVariant(
            id: "A", name: "Brushstroke",
            blurb: "One confident stroke; the next bud opens inside its tail.",
            inkDuration: 0.42, budDelay: 0.26, budDuration: 0.34, budOvershoot: false
        ),
        MotionLabStageVariant(
            id: "B", name: "Unfurl",
            blurb: "The leaf finishes, a breath, then the bud blooms with a slight overshoot.",
            inkDuration: 0.62, budDelay: 0.72, budDuration: 0.46, budOvershoot: true
        ),
        MotionLabStageVariant(
            id: "C", name: "Exhale",
            blurb: "Slow, calm ink; the bud opening rides the last third.",
            inkDuration: 0.90, budDelay: 0.62, budDuration: 0.55, budOvershoot: false
        )
    ]
}

struct MotionLabCeremonyVariant: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let stemDuration: Double
    /// Per-leaf pop duration as the stem passes it.
    let leafPop: Double
    /// Pause between the stem completing and the bird setting off.
    let birdDelay: Double
    let birdDuration: Double
    let birdGlides: Bool

    var birdStart: Double { stemDuration + birdDelay }
    var total: Double { birdStart + birdDuration }

    static let all: [MotionLabCeremonyVariant] = [
        MotionLabCeremonyVariant(
            id: "A", name: "Brisk",
            blurb: "The branch grows in a second; the bird drops straight onto the tip.",
            stemDuration: 1.0, leafPop: 0.30, birdDelay: 0.10, birdDuration: 0.35, birdGlides: false
        ),
        MotionLabCeremonyVariant(
            id: "B", name: "Grand",
            blurb: "A fuller growth with a beat before the bird settles.",
            stemDuration: 1.6, leafPop: 0.40, birdDelay: 0.15, birdDuration: 0.50, birdGlides: false
        ),
        MotionLabCeremonyVariant(
            id: "C", name: "Slow bloom",
            blurb: "The slowest growth, a held pause, then the bird glides in.",
            stemDuration: 2.2, leafPop: 0.50, birdDelay: 0.30, birdDuration: 0.70, birdGlides: true
        )
    ]
}

struct MotionLabHapticTuning: Identifiable {
    struct Transient {
        let intensity: Float
        let sharpness: Float
    }

    enum MoveOnShape {
        case swellAndPeak
        case warmSwell
        case risingTriplet
    }

    let id: String
    let name: String
    let blurb: String
    let tick: Transient
    let log: Transient
    let skip: Transient
    let moveOnShape: MoveOnShape

    static let all: [MotionLabHapticTuning] = [
        MotionLabHapticTuning(
            id: "A", name: "Crisp",
            blurb: "Bright ticks, a rigid log tap; the ceremony swells and lands with a peak.",
            tick: Transient(intensity: 0.35, sharpness: 0.85),
            log: Transient(intensity: 1.0, sharpness: 0.65),
            skip: Transient(intensity: 0.45, sharpness: 0.15),
            moveOnShape: .swellAndPeak
        ),
        MotionLabHapticTuning(
            id: "B", name: "Warm",
            blurb: "Rounder ticks and tap; the ceremony is one long warm swell.",
            tick: Transient(intensity: 0.45, sharpness: 0.50),
            log: Transient(intensity: 0.90, sharpness: 0.45),
            skip: Transient(intensity: 0.55, sharpness: 0.10),
            moveOnShape: .warmSwell
        ),
        MotionLabHapticTuning(
            id: "C", name: "Feather",
            blurb: "Light, sharp ticks; the ceremony climbs three steps and blooms.",
            tick: Transient(intensity: 0.28, sharpness: 0.70),
            log: Transient(intensity: 0.80, sharpness: 0.80),
            skip: Transient(intensity: 0.35, sharpness: 0.20),
            moveOnShape: .risingTriplet
        )
    ]
}
