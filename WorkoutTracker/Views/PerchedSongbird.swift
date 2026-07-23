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

/// The songbird silhouette in a 120×72 design space, facing trailing: a plump
/// leaf-body with a rounded head, a short beak, and a pointed tail.
struct SongbirdBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 4, y: 40)) // tail tip
        path.addCurve(
            to: CGPoint(x: 86, y: 8), // long back rising to the head crown
            control1: CGPoint(x: 26, y: 6),
            control2: CGPoint(x: 58, y: 2)
        )
        path.addCurve(
            to: CGPoint(x: 112, y: 22), // head crown down to the beak base
            control1: CGPoint(x: 98, y: 8),
            control2: CGPoint(x: 108, y: 14)
        )
        path.addLine(to: CGPoint(x: 120, y: 27)) // upper beak to tip
        path.addLine(to: CGPoint(x: 104, y: 30)) // beak tip to lower beak
        path.addCurve(
            to: CGPoint(x: 72, y: 56), // throat/breast down to the belly
            control1: CGPoint(x: 98, y: 44),
            control2: CGPoint(x: 88, y: 54)
        )
        path.addCurve(
            to: CGPoint(x: 4, y: 40), // belly sweeping back to the tail
            control1: CGPoint(x: 44, y: 60),
            control2: CGPoint(x: 22, y: 54)
        )
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 120, y: rect.height / 72))
    }
}

/// The cream wing-hint arced across the songbird's upper body, in the same
/// 120×72 space.
struct SongbirdWingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 30, y: 32))
        path.addCurve(
            to: CGPoint(x: 82, y: 20),
            control1: CGPoint(x: 46, y: 22),
            control2: CGPoint(x: 66, y: 18)
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
    private var leafSize: CGSize { CGSize(width: width * 0.16, height: width * 0.16 * 24.0 / 60.0) }

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

                SongbirdGlyph(width: birdWidth, fill: palette.birdFill, rib: palette.birdRib)
                    .position(x: crown.x, y: crown.y - birdWidth * 0.6 * 0.5 + size.height * 0.02)
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
        static var leafSize: CGSize { CGSize(width: leafLength, height: leafLength * 24.0 / 60.0) }
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
                SongbirdGlyph(width: Metrics.birdWidth, fill: palette.birdFill, rib: palette.birdRib)
                    .position(x: tip.x - Metrics.birdWidth * 0.22, y: tip.y - Metrics.birdWidth * 0.6 * 0.42)
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

    private func stemPoint(t: CGFloat, in size: CGSize) -> CGPoint {
        let p0 = CGPoint(x: Metrics.leadInset, y: size.height * Metrics.rootY)
        let p1 = CGPoint(x: size.width - Metrics.trailInset, y: size.height * Metrics.tipY)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - Metrics.bow)
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * control.x + t * t * p1.x,
            y: mt * mt * p0.y + 2 * mt * t * control.y + t * t * p1.y
        )
    }

    private func stemAngle(t: CGFloat, in size: CGSize) -> Angle {
        let p0 = CGPoint(x: Metrics.leadInset, y: size.height * Metrics.rootY)
        let p1 = CGPoint(x: size.width - Metrics.trailInset, y: size.height * Metrics.tipY)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - Metrics.bow)
        let mt = 1 - t
        let dx = 2 * mt * (control.x - p0.x) + 2 * t * (p1.x - control.x)
        let dy = 2 * mt * (control.y - p0.y) + 2 * t * (p1.y - control.y)
        return Angle(radians: atan2(dy, dx))
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
