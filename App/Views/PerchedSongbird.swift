import SwiftUI

/// The perched songbird — a drawing in the **leaf language** (not the colophon's
/// glyph), the second Sunbird form (DESIGN.md §6, "The Two Perches"). It lives in
/// exactly two homes: centered on the Sheet-connect screen, and at the Move On
/// ceremony branch tip where it replaces the colophon. **The Bird Re-lights Like
/// a Leaf:** by day it takes the action green; at night it takes foliage ink with
/// a cream wing-hint and no glow — driven entirely by `palette.birdFill` /
/// `palette.birdRib`.
struct SongbirdGlyph: View {
    var width: CGFloat = 120
    let fill: Color
    let rib: Color

    private var height: CGFloat { width * 0.6 }

    var body: some View {
        ZStack {
            SongbirdBodyShape().fill(fill)
            SongbirdWingShape()
                .stroke(rib, style: StrokeStyle(lineWidth: max(1, width * 0.018), lineCap: .round))
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// The songbird silhouette in a 120×72 design space, facing trailing (right):
/// a plump breast under a **distinct rounded head** that bulges above the back,
/// a short wedge beak, and a pointed tail — the plump songbird of pick
/// sunbird-moments-c, not the almond/leaf body the first pass drew (owner
/// report #3). The back rises from the tail, dips slightly at the neck, then the
/// head crowns high before dropping to the beak; the breast and belly round out
/// full beneath.
struct SongbirdBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3, y: 34)) // pointed tail tip, trailing left
        // The back sweeps up from the tail to a low shoulder, easing into the neck.
        path.addCurve(
            to: CGPoint(x: 72, y: 20),
            control1: CGPoint(x: 26, y: 12),
            control2: CGPoint(x: 56, y: 14)
        )
        // The rounded head: up over a high crown, then down the face to the beak base.
        path.addCurve(
            to: CGPoint(x: 112, y: 30),
            control1: CGPoint(x: 86, y: 2),
            control2: CGPoint(x: 116, y: 12)
        )
        // The short wedge beak, pointing trailing.
        path.addLine(to: CGPoint(x: 123, y: 33))
        path.addLine(to: CGPoint(x: 108, y: 36))
        // The throat and plump breast rounding down to the belly.
        path.addCurve(
            to: CGPoint(x: 55, y: 66),
            control1: CGPoint(x: 96, y: 54),
            control2: CGPoint(x: 82, y: 66)
        )
        // The round belly sweeping back up to the pointed tail.
        path.addCurve(
            to: CGPoint(x: 3, y: 34),
            control1: CGPoint(x: 28, y: 66),
            control2: CGPoint(x: 8, y: 52)
        )
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 120, y: rect.height / 72))
    }
}

/// The cream wing-hint arced across the songbird's plump body, in the same
/// 120×72 space.
struct SongbirdWingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 30, y: 40))
        path.addCurve(
            to: CGPoint(x: 88, y: 28),
            control1: CGPoint(x: 48, y: 40),
            control2: CGPoint(x: 70, y: 30)
        )
        return path.applying(CGAffineTransform(scaleX: rect.width / 120, y: rect.height / 72))
    }
}

/// The Sheet-connect perch (DESIGN.md §5.8, picks sunbird-moments-c/-e): a flat,
/// calm composition — a shallow bowed branch with a small leaf drooping at each
/// end and the songbird perched at its crown.
struct ConnectPerch: View {
    @Environment(\.themePalette) private var palette
    var width: CGFloat = 240

    private var height: CGFloat { width * 0.62 }
    private var birdWidth: CGFloat { width * 0.52 }
    private var leafSize: CGSize { CGSize(width: width * 0.16, height: width * 0.16 * LeafShape.aspectRatio) }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                let leftEnd = CGPoint(x: size.width * 0.10, y: size.height * 0.72)
                let rightEnd = CGPoint(x: size.width * 0.90, y: size.height * 0.72)
                let crown = CGPoint(x: size.width * 0.50, y: size.height * 0.55)

                PerchArc(leftEnd: leftEnd, rightEnd: rightEnd, crown: crown)
                    .stroke(palette.stem, style: StrokeStyle(lineWidth: width * 0.012, lineCap: .round))

                BranchLeaf(fill: palette.leafFill, rib: palette.leafRib, size: leafSize)
                    .rotationEffect(.degrees(58))
                    .position(x: leftEnd.x + leafSize.width * 0.1, y: leftEnd.y + leafSize.height * 0.9)

                BranchLeaf(fill: palette.leafFill, rib: palette.leafRib, size: leafSize)
                    .rotationEffect(.degrees(-58))
                    .position(x: rightEnd.x - leafSize.width * 0.1, y: rightEnd.y + leafSize.height * 0.9)

                // Seat the bird *on* the branch: the plump belly (≈0.92 of the glyph
                // height) meets the crown with a few points of overlap so it reads
                // perched, not floating.
                let birdHeight = birdWidth * 0.6
                SongbirdGlyph(width: birdWidth, fill: palette.birdFill, rib: palette.birdRib)
                    .position(x: crown.x - birdWidth * 0.05, y: crown.y - birdHeight * 0.42 + 4)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// The ceremony branch (DESIGN.md §5.7, picks sunbird-moments-a/-d): a stem that
/// climbs from a low leading root to a high trailing tip, one inked leaf growing
/// off it in alternation, with the songbird perched at the tip in place of the
/// colophon. The count is decorative — the ceremony is brand, not a per-Set
/// ledger (that reading lives on the stage) — so the branch stays byte-stable.
struct CeremonyBranch: View {
    @Environment(\.themePalette) private var palette
    var leafCount: Int = 8

    private enum Metrics {
        static let height: CGFloat = 220
        static let leadInset: CGFloat = 30
        static let trailInset: CGFloat = 40
        static let rootY: CGFloat = 0.88
        static let tipY: CGFloat = 0.14
        static let bow: CGFloat = 40
        static let firstT: CGFloat = 0.12
        static let lastT: CGFloat = 0.90
        static let leafLength: CGFloat = 52
        static var leafSize: CGSize { CGSize(width: leafLength, height: leafLength * LeafShape.aspectRatio) }
        static let leafOffset: CGFloat = 22
        static let leafTilt: CGFloat = 20
        static let stemWidth: CGFloat = 2.4
        static let birdWidth: CGFloat = 96
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                StemArc(
                    leadInset: Metrics.leadInset,
                    trailInset: Metrics.trailInset,
                    rootY: Metrics.rootY,
                    tipY: Metrics.tipY,
                    bow: Metrics.bow
                )
                .stroke(palette.stem, style: StrokeStyle(lineWidth: Metrics.stemWidth, lineCap: .round))

                ForEach(0..<max(0, leafCount), id: \.self) { index in
                    let point = stemPoint(t: leafT(index), in: size)
                    let angle = stemAngle(t: leafT(index), in: size)
                    let above = index.isMultiple(of: 2)
                    BranchLeaf(fill: palette.leafFill, rib: palette.leafRib, size: Metrics.leafSize)
                        .rotationEffect(angle + .degrees(above ? -Metrics.leafTilt : Metrics.leafTilt))
                        .offset(y: above ? -Metrics.leafOffset : Metrics.leafOffset)
                        .position(point)
                }

                let tip = stemPoint(t: 1, in: size)
                // Seat the plump belly (≈0.92 of the glyph height) on the stem's tip.
                SongbirdGlyph(width: Metrics.birdWidth, fill: palette.birdFill, rib: palette.birdRib)
                    .position(x: tip.x - Metrics.birdWidth * 0.22, y: tip.y - Metrics.birdWidth * 0.6 * 0.42 + 4)
            }
        }
        .frame(height: Metrics.height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func leafT(_ index: Int) -> CGFloat {
        guard leafCount > 1 else { return (Metrics.firstT + Metrics.lastT) / 2 }
        let span = Metrics.lastT - Metrics.firstT
        return Metrics.firstT + span * CGFloat(index) / CGFloat(leafCount - 1)
    }

    private func stemCurve(in size: CGSize) -> QuadraticBezier {
        let p0 = CGPoint(x: Metrics.leadInset, y: size.height * Metrics.rootY)
        let p1 = CGPoint(x: size.width - Metrics.trailInset, y: size.height * Metrics.tipY)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - Metrics.bow)
        return QuadraticBezier(start: p0, control: control, end: p1)
    }

    private func stemPoint(t: CGFloat, in size: CGSize) -> CGPoint {
        stemCurve(in: size).point(at: t)
    }

    private func stemAngle(t: CGFloat, in size: CGSize) -> Angle {
        let tangent = stemCurve(in: size).tangent(at: t)
        return Angle(radians: atan2(tangent.dy, tangent.dx))
    }
}

/// One inked leaf with a cream rib, in the shared token-sheet leaf language
/// (reusing `LeafShape` / `RibShape` from the living stage).
private struct BranchLeaf: View {
    let fill: Color
    let rib: Color
    let size: CGSize

    var body: some View {
        ZStack {
            LeafShape().fill(fill)
            RibShape().stroke(rib, style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The connect perch's shallow bowed branch — a quadratic arc humping gently up
/// between its two low ends.
private struct PerchArc: Shape {
    let leftEnd: CGPoint
    let rightEnd: CGPoint
    let crown: CGPoint

    func path(in _: CGRect) -> Path {
        let control = CGPoint(x: crown.x, y: crown.y - (leftEnd.y - crown.y))
        var path = Path()
        path.move(to: leftEnd)
        path.addQuadCurve(to: rightEnd, control: control)
        return path
    }
}

/// The ceremony stem's climbing path — a quadratic bezier from a low leading root
/// to a high trailing tip, matching the living stage's climb.
private struct StemArc: Shape {
    let leadInset: CGFloat
    let trailInset: CGFloat
    let rootY: CGFloat
    let tipY: CGFloat
    let bow: CGFloat

    func path(in rect: CGRect) -> Path {
        let p0 = CGPoint(x: leadInset, y: rect.height * rootY)
        let p1 = CGPoint(x: rect.width - trailInset, y: rect.height * tipY)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - bow)
        var path = Path()
        path.move(to: p0)
        path.addQuadCurve(to: p1, control: control)
        return path
    }
}

#Preview("Connect perch") {
    ZStack {
        Theme.palette(for: .day).gradient.ignoresSafeArea()
        ConnectPerch()
            .environment(\.themePalette, Theme.palette(for: .day))
    }
}

#Preview("Ceremony branch") {
    ZStack {
        Theme.palette(for: .night).gradient.ignoresSafeArea()
        CeremonyBranch()
            .environment(\.themePalette, Theme.palette(for: .night))
    }
    .preferredColorScheme(.dark)
}
