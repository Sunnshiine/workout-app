import SwiftUI

// The shared Greenhouse drawing language, ported 1:1 from the locked HTML prototypes.
// All shapes draw in absolute local coordinates and are placed with affine transforms,
// mirroring the SVG `translate rotate scale translate(0,-8)` chain so stroke widths
// divide by scale exactly as the originals do.

/// The Greenhouse leaf — 60×16 units, anchored at its stem-side tip (0, 8).
struct MotionLabLeafShape: Shape {
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 8))
        p.addCurve(to: CGPoint(x: 60, y: 8), control1: CGPoint(x: 15, y: 2.3), control2: CGPoint(x: 41, y: 3.3))
        p.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 41, y: 21.7), control2: CGPoint(x: 15, y: 22.6))
        p.closeSubpath()
        return p
    }
}

struct MotionLabLeafRibShape: Shape {
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 8.1))
        p.addCurve(to: CGPoint(x: 56, y: 8.1), control1: CGPoint(x: 20, y: 9.8), control2: CGPoint(x: 40, y: 9.6))
        return p
    }
}

/// The accepted d2 songbird (#412/#414), local coordinates around its perch contact point (0, 0).
struct MotionLabBirdShape: Shape {
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -33, y: -5))
        p.addCurve(to: CGPoint(x: -11, y: -18), control1: CGPoint(x: -24, y: -10), control2: CGPoint(x: -17, y: -14))
        p.addCurve(to: CGPoint(x: 8, y: -32), control1: CGPoint(x: -7, y: -27), control2: CGPoint(x: 0, y: -32))
        p.addCurve(to: CGPoint(x: 21, y: -25), control1: CGPoint(x: 14, y: -32), control2: CGPoint(x: 18.5, y: -29))
        p.addLine(to: CGPoint(x: 29, y: -21.5))
        p.addCurve(to: CGPoint(x: 19, y: -12), control1: CGPoint(x: 23.5, y: -18.5), control2: CGPoint(x: 21, y: -16))
        p.addCurve(to: CGPoint(x: 3, y: 0), control1: CGPoint(x: 16.5, y: -5), control2: CGPoint(x: 11, y: -0.5))
        p.addCurve(to: CGPoint(x: -10.5, y: -3.5), control1: CGPoint(x: -2, y: 0.3), control2: CGPoint(x: -6.5, y: -1))
        p.addCurve(to: CGPoint(x: -23.5, y: -2.2), control1: CGPoint(x: -14.5, y: -5.5), control2: CGPoint(x: -19, y: -3))
        p.addCurve(to: CGPoint(x: -33, y: -5), control1: CGPoint(x: -27, y: -1.8), control2: CGPoint(x: -30.5, y: -3))
        p.closeSubpath()
        return p
    }
}

struct MotionLabBirdRibShape: Shape {
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 12, y: -19))
        p.addCurve(to: CGPoint(x: -11, y: -14), control1: CGPoint(x: 4, y: -22), control2: CGPoint(x: -4, y: -20))
        return p
    }
}

struct MotionLabStemShape: Shape {
    let stem: MotionLabStem

    func path(in _: CGRect) -> Path { stem.path }
}

/// Per-frame render channels for one Set node, produced by the moment clocks.
struct MotionLabLeafChannels {
    var leafInk: Double = 0
    var leafAlpha: Double = 1
    var skipDraw: Double = 0
    var budPresence: Double = 0
    var budScale: Double = 1
    var futureAlpha: Double = 0
    var pop: Double = 1
}

/// One Set node on a branch, placed by the same transform chain as the SVG originals.
struct MotionLabLeafNodeView: View {
    let node: MotionLabSetNode
    let stem: MotionLabStem
    let channels: MotionLabLeafChannels

    var body: some View {
        ZStack(alignment: .topLeading) {
            if channels.futureAlpha > 0 {
                MotionLabLeafShape()
                    .stroke(MotionLabInk.futureStroke, lineWidth: 1.2 / node.scale)
                    .opacity(channels.futureAlpha)
            }
            if channels.budPresence > 0 {
                budLayer
            }
            if channels.leafInk > 0 {
                leafLayer
            }
            if channels.skipDraw > 0 {
                MotionLabLeafShape()
                    .trim(from: 0, to: channels.skipDraw)
                    .stroke(
                        MotionLabInk.skipStroke,
                        style: StrokeStyle(lineWidth: 1.2 / node.scale, dash: [5 / node.scale, 4 / node.scale])
                    )
                    .opacity(channels.leafAlpha)
            }
        }
        .transformEffect(nodeTransform)
    }

    private var budLayer: some View {
        ZStack(alignment: .topLeading) {
            MotionLabLeafShape()
                .fill(MotionLabInk.budFill)
            MotionLabLeafShape()
                .stroke(MotionLabInk.budStroke, lineWidth: 2.2 / node.scale)
            MotionLabLeafRibShape()
                .stroke(MotionLabInk.budRib, style: StrokeStyle(lineWidth: 1.2 / node.scale, lineCap: .round))
        }
        .opacity(channels.budPresence)
        .transformEffect(anchoredScale(channels.budScale))
    }

    private var leafLayer: some View {
        ZStack(alignment: .topLeading) {
            MotionLabLeafShape()
                .fill(MotionLabInk.leafFill)
            MotionLabLeafRibShape()
                .stroke(MotionLabInk.leafRib, style: StrokeStyle(lineWidth: 1.2 / node.scale, lineCap: .round))
        }
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: 64 * channels.leafInk, height: 32)
                .offset(x: -2, y: -4)
        }
        .opacity(channels.leafAlpha)
    }

    /// translate(stem point) · rotate(tangent + side·spread) · scale(node) · translate(0,-8),
    /// with the ceremony pop applied first, in leaf-local space about the anchor (0, 8).
    private var nodeTransform: CGAffineTransform {
        let point = stem.point(atFraction: node.t)
        let degrees = stem.angleDegrees(atFraction: node.t) + node.side * node.spread
        var t = CGAffineTransform(translationX: point.x, y: point.y)
        t = t.rotated(by: degrees * .pi / 180)
        t = t.scaledBy(x: node.scale, y: node.scale)
        t = t.translatedBy(x: 0, y: -8)
        guard channels.pop != 1 else { return t }
        t = t.translatedBy(x: 0, y: 8)
        t = t.scaledBy(x: channels.pop, y: channels.pop)
        t = t.translatedBy(x: 0, y: -8)
        return t
    }

    private func anchoredScale(_ scale: Double) -> CGAffineTransform {
        guard scale != 1 else { return .identity }
        var t = CGAffineTransform(translationX: 0, y: 8)
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: 0, y: -8)
        return t
    }
}

/// Living paper (#420): the layered wash recipe, day values — organic light, never objects.
struct MotionLabPaper: View {
    var body: some View {
        LinearGradient(
            colors: [MotionLabInk.paperTop, MotionLabInk.paperBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [MotionLabInk.labColor(0xF7F0CF, 0.55), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 430
            )
        }
        .overlay {
            RadialGradient(
                colors: [MotionLabInk.labColor(0xBFE8CF, 0.35), .clear],
                center: UnitPoint(x: 1.06, y: 0.45),
                startRadius: 0,
                endRadius: 300
            )
        }
        .overlay {
            RadialGradient(
                colors: [MotionLabInk.labColor(0x9DBB90, 0.30), .clear],
                center: UnitPoint(x: 0.5, y: 1.08),
                startRadius: 0,
                endRadius: 380
            )
        }
    }
}
