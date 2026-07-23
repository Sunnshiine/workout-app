import SwiftUI

/// The living stage's branch — the page's one icon and its only piece of flora
/// (DESIGN.md §5.1, picks session-stage-a/-d). A 2px round-cap stem *climbs* the
/// page from a low leading root to a high trailing tip; along it, one inked leaf
/// per Logged Set, a dashed-outline leaf per Skipped Set, a cream bud with a
/// green stroke for the active Set (carrying the page's one glow at Night), and
/// faint **angled future strokes** for the Pending Sets still ahead. Even before
/// any Set logs it reads as a rising stem, not a horizontal progress slider
/// (ledger §4.1). The branch stands textless; the plain `Set N of M` head carries
/// the reading in words. Node states come from
/// `SessionStagePresentation.branchNodeStates`, so the branch owns geometry only.
struct SessionStageBranch: View {
    let sets: [ExerciseSet]
    var activeSetID: ActiveSetID?
    /// Tapping a node focuses its Set — matching the retired dots' behavior. `nil`
    /// keeps the branch a passive glyph.
    var onTap: ((ExerciseSet) -> Void)?
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Metrics {
        static let height: CGFloat = 156
        static let leadInset: CGFloat = 24
        static let trailInset: CGFloat = 28
        static let rootY: CGFloat = 0.82 // fraction of height — the low leading root
        static let tipY: CGFloat = 0.13 // fraction of height — the high trailing tip
        static let bow: CGFloat = 30 // upward bow of the climbing stem
        static let firstNodeT: CGFloat = 0.16
        static let lastNodeT: CGFloat = 0.84
        static let leafLength: CGFloat = 46
        static var leafSize: CGSize { CGSize(width: leafLength, height: leafLength * 24.0 / 60.0) }
        static let leafOffset: CGFloat = 20 // perpendicular distance off the stem
        static let leafTilt: CGFloat = 20 // extra outward tilt, alternating
        static let budDiameter: CGFloat = 15
        static let futureLength: CGFloat = 22
        static let futureTilt: CGFloat = 38 // branch off the stem so the mark reads as a future twig
        static let futureOffset: CGFloat = 7 // lift the mark's midpoint just off the stem
        static let stemWidth: CGFloat = 2
    }

    private var nodes: [(set: ExerciseSet, state: BranchNodeState)] {
        Array(zip(sets, SessionStagePresentation.branchNodeStates(for: sets, activeSetID: activeSetID)))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                StemPath(
                    leadInset: Metrics.leadInset,
                    trailInset: Metrics.trailInset,
                    rootY: Metrics.rootY,
                    tipY: Metrics.tipY,
                    bow: Metrics.bow
                )
                .stroke(palette.stem, style: StrokeStyle(lineWidth: Metrics.stemWidth, lineCap: .round))

                ForEach(Array(nodes.enumerated()), id: \.element.set.persistentModelID) { index, node in
                    let point = stemPoint(t: nodeT(index), in: size)
                    let angle = stemAngle(t: nodeT(index), in: size)
                    nodeCell(node.set, state: node.state, above: index.isMultiple(of: 2), angle: angle)
                        .position(point)
                }
            }
        }
        .frame(height: Metrics.height)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : Theme.wingAnimation(duration: Theme.Motion.leafInk), value: activeSetID)
        .animation(reduceMotion ? nil : Theme.wingAnimation(duration: Theme.Motion.leafInk), value: sets.count)
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
    }

    // MARK: - Nodes

    @ViewBuilder
    private func nodeCell(
        _ set: ExerciseSet,
        state: BranchNodeState,
        above: Bool,
        angle: Angle
    ) -> some View {
        let glyph = nodeGlyph(state, above: above, angle: angle)
        if let onTap {
            Button {
                onTap(set)
            } label: {
                glyph
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(set.index + 1), \(SetRowPresentation(set: set).title)")
        } else {
            glyph
        }
    }

    @ViewBuilder
    private func nodeGlyph(_ state: BranchNodeState, above: Bool, angle: Angle) -> some View {
        switch state {
        case .leaf:
            leaf(filled: true, above: above, angle: angle)
                .transition(.opacity)
        case .dashedLeaf:
            leaf(filled: false, above: above, angle: angle)
                .transition(.opacity)
        case .bud:
            // One Log, One Fill (ledger §4.4): the next bud *wakes* on its own
            // tokenized timing — 0.34s starting 0.26s into the previous leaf's
            // ink — reading as a bud opening, never a second leaf filling.
            BranchBudGlyph(fill: palette.budFill, stroke: palette.budStroke, glow: palette.budGlow)
                .frame(width: Metrics.budDiameter, height: Metrics.budDiameter)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .animation(
                    reduceMotion
                        ? nil
                        : Theme.wingAnimation(duration: Theme.Motion.budOpen).delay(Theme.Motion.budOpenDelay),
                    value: activeSetID
                )
        case .future:
            // A faint stroke branching off the climbing stem at an angle — the
            // preview of where a leaf will grow, never a circular dot (ledger §4.1).
            Capsule()
                .fill(palette.futureStroke)
                .frame(width: Metrics.futureLength, height: Metrics.stemWidth)
                .rotationEffect(angle + Angle(degrees: above ? -Metrics.futureTilt : Metrics.futureTilt))
                .offset(y: above ? -Metrics.futureOffset : Metrics.futureOffset)
        }
    }

    private func leaf(filled: Bool, above: Bool, angle: Angle) -> some View {
        // The leaf grows off the stem: aligned to the stem's climb, then tilted
        // outward, and lifted perpendicular so its base meets the stem.
        let tilt = Angle(degrees: above ? -Metrics.leafTilt : Metrics.leafTilt)
        let lift = above ? -Metrics.leafOffset : Metrics.leafOffset
        return BranchLeafGlyph(
            filled: filled,
            fill: palette.leafFill,
            rib: palette.leafRib,
            dash: palette.skipStroke,
            size: Metrics.leafSize
        )
        .rotationEffect(angle + tilt)
        .offset(y: lift)
    }

    // MARK: - Stem geometry

    private func nodeT(_ index: Int) -> CGFloat {
        guard nodes.count > 1 else { return 0.5 }
        let span = Metrics.lastNodeT - Metrics.firstNodeT
        return Metrics.firstNodeT + span * CGFloat(index) / CGFloat(nodes.count - 1)
    }

    /// A point on the climbing stem at parameter `t` (a quadratic bezier bowed
    /// gently upward). Root at low leading, tip at high trailing.
    private func stemPoint(t: CGFloat, in size: CGSize) -> CGPoint {
        let p0 = CGPoint(x: Metrics.leadInset, y: size.height * Metrics.rootY)
        let p1 = CGPoint(x: size.width - Metrics.trailInset, y: size.height * Metrics.tipY)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - Metrics.bow)
        let mt = 1 - t
        let x = mt * mt * p0.x + 2 * mt * t * control.x + t * t * p1.x
        let y = mt * mt * p0.y + 2 * mt * t * control.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    /// The stem's tangent angle at parameter `t`, so leaves and future strokes
    /// align with the climb.
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

/// The climbing stem's path — a quadratic bezier root→tip, computed from the
/// same metrics the nodes use so glyphs land on the drawn stem.
private struct StemPath: Shape {
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

/// One leaf: an inked silhouette (with an optional cream rib) for a Logged Set, or
/// a dashed outline for a Skipped Set (token sheet §Stage & branch — geometry
/// kept verbatim from the locked design).
private struct BranchLeafGlyph: View {
    let filled: Bool
    let fill: Color
    let rib: Color?
    let dash: Color
    let size: CGSize

    var body: some View {
        ZStack {
            if filled {
                LeafShape().fill(fill)
                if let rib {
                    RibShape().stroke(rib, style: StrokeStyle(lineWidth: 1.2 * 0.5, lineCap: .round))
                }
            } else {
                LeafShape().stroke(
                    dash,
                    style: StrokeStyle(lineWidth: 1.2 * 0.5, lineCap: .round, dash: [5, 4])
                )
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The active Set's cream bud with a green stroke; `glow` lights it at Night and is
/// `nil` (unlit) by Day.
private struct BranchBudGlyph: View {
    let fill: Color
    let stroke: Color
    let glow: Color?

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(stroke, lineWidth: 2.2 * 0.5))
            .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 7)
    }
}

/// The token-sheet leaf silhouette (`M0 8 C 15 2.3, 41 3.3, 60 8 C 41 21.7, 15 22.6, 0 8 Z`)
/// in a 60×24 design space, scaled into the drawing rect.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 8))
        path.addCurve(to: CGPoint(x: 60, y: 8), control1: CGPoint(x: 15, y: 2.3), control2: CGPoint(x: 41, y: 3.3))
        path.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 41, y: 21.7), control2: CGPoint(x: 15, y: 22.6))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 60, y: rect.height / 24))
    }
}

/// The leaf's central rib (`M4 8.1 C 20 9.8, 40 9.6, 56 8.1`) in the same 60×24 space.
struct RibShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 4, y: 8.1))
        path.addCurve(to: CGPoint(x: 56, y: 8.1), control1: CGPoint(x: 20, y: 9.8), control2: CGPoint(x: 40, y: 9.6))
        return path.applying(CGAffineTransform(scaleX: rect.width / 60, y: rect.height / 24))
    }
}
