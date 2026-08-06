import SwiftUI

/// The living stage's branch — the page's one icon and its only piece of flora
/// (DESIGN.md §5.1, pick session-stage-a). A 2px round-cap stem *climbs* the
/// page from a low leading root to a high trailing tip; every mark along it is
/// **the same slender blade** in a different state: inked per Logged Set, a
/// dashed outline per Skipped Set, cream-filled inside a green stroke for the
/// active Set (logging inks it solid — the pick's clever leaf fill; it carries
/// the page's one glow at Night), and a faint **ghost outline** for each Pending
/// Set still ahead. Nodes anchor to a terminal at t=0.80 and step down the stem,
/// so even 2–3 Sets read as one sprig on a full-length stem, never a horizontal
/// progress slider (ledger §4.1). The branch stands textless; the plain
/// `Set N of M` head carries the reading in words. Node states come from
/// `SessionStagePresentation.branchNodeStates`, so the branch owns geometry only.
struct SessionStageBranch: View {
    let sets: [ExerciseSet]
    var activeSetID: ActiveSetID?
    /// A Superset partner's Sets. When present the branch becomes **one forked
    /// stem** (DESIGN.md §5.4): the focused Exercise's `sets` climb at full stroke
    /// and alone carry the cream-filled active leaf, while the partner's Sets grow
    /// along a shorter drooping lateral that never carries it. `nil` keeps the
    /// page a single climbing stem.
    var partnerSets: [ExerciseSet]?
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
        static let firstNodeT: CGFloat = 0.16 // the span floor node steps never pass
        static let lastNodeT: CGFloat = 0.80 // the terminal node every cluster anchors to
        static let maxNodeStep: CGFloat = 0.24 // cap the gap so few Sets cluster like a real sprig
        static let leafLength: CGFloat = 46
        // Measured off the pick: above-blades stand steeply with a slight back
        // lean, below-blades droop forward — both lean toward the tip.
        static let leafTiltAbove: CGFloat = 43
        static let leafTiltBelow: CGFloat = 50
        static let ghostScale: CGFloat = 0.72 // a future is a smaller ghost of the leaf to come
        static let stemWidth: CGFloat = 2
    }

    /// The partner's drooping lateral (DESIGN.md §5.4): a thinner, shorter stem
    /// that forks off the focused stem's lower reach and droops down-trailing,
    /// carrying the partner's leaves but never the active leaf.
    private enum PartnerMetrics {
        static let stemWidth: CGFloat = 1.6
        static let forkT: CGFloat = 0.30 // where on the focused stem the lateral forks
        static let endX: CGFloat = 0.62 // fraction of width for the drooping tip
        static let endY: CGFloat = 0.99 // fraction of height — the tip droops low
        static let droop: CGFloat = 30 // downward bow of the drooping lateral
        static let firstNodeT: CGFloat = 0.42
        static let lastNodeT: CGFloat = 0.9
        static let maxNodeStep: CGFloat = 0.2
        static let leafLength: CGFloat = 34 // subordinate to the focused leaf
    }

    private var nodes: [(set: ExerciseSet, state: BranchNodeState)] {
        Array(zip(sets, SessionStagePresentation.branchNodeStates(for: sets, activeSetID: activeSetID)))
    }

    private var partnerNodes: [(set: ExerciseSet, state: BranchNodeState)] {
        guard let partnerSets else { return [] }
        return Array(zip(partnerSets, SessionStagePresentation.supersetPartnerNodeStates(for: partnerSets)))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if partnerSets != nil {
                    partnerBranch(in: size)
                }

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
            blade(.inked(fill: palette.leafFill, rib: palette.leafRib), above: above, angle: angle)
                .transition(.opacity)
        case .dashedLeaf:
            blade(.dashed(palette.skipStroke), above: above, angle: angle)
                .transition(.opacity)
        case .bud:
            // One Log, One Fill (ledger §4.4): the active blade *wakes* on its
            // own tokenized timing — 0.34s starting 0.26s into the previous
            // leaf's ink — reading as a cream leaf opening (that logging then
            // inks solid), never a second leaf filling.
            blade(.cream(fill: palette.budFill, stroke: palette.budStroke, glow: palette.budGlow), above: above, angle: angle)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .animation(
                    reduceMotion
                        ? nil
                        : Theme.wingAnimation(duration: Theme.Motion.budOpen).delay(Theme.Motion.budOpenDelay),
                    value: activeSetID
                )
        case .future:
            // A ghost of the leaf to come — a faint, smaller outline of the same
            // blade, never an angled stroke or a circular dot (verdict, §4.1).
            blade(.ghost(palette.futureStroke), above: above, angle: angle, length: Metrics.leafLength * Metrics.ghostScale)
        }
    }

    /// One blade off the stem: its base sits on the node, and it angles up- or
    /// down-forward off the stem's climb, alternating sides. The pre-rotation
    /// x-offset moves the base onto the rotation anchor, so the blade pivots
    /// around where it meets the stem.
    private func blade(
        _ style: BranchBladeGlyph.Style,
        above: Bool,
        angle: Angle,
        length: CGFloat = Metrics.leafLength
    ) -> some View {
        let size = CGSize(width: length, height: length * LeafShape.aspectRatio)
        let tilt = Angle(degrees: above ? -Metrics.leafTiltAbove : Metrics.leafTiltBelow)
        return BranchBladeGlyph(style: style, size: size)
            .offset(x: size.width / 2)
            .rotationEffect(angle + tilt)
    }

    // MARK: - Partner lateral

    @ViewBuilder
    private func partnerBranch(in size: CGSize) -> some View {
        let fork = stemPoint(t: PartnerMetrics.forkT, in: size)
        ZStack {
            LateralPath(fork: fork, tip: partnerTip(in: size), droop: PartnerMetrics.droop)
                .stroke(
                    palette.supersetPartnerBranch,
                    style: StrokeStyle(lineWidth: PartnerMetrics.stemWidth, lineCap: .round)
                )

            ForEach(Array(partnerNodes.enumerated()), id: \.element.set.persistentModelID) { index, node in
                let point = partnerPoint(t: partnerNodeT(index), fork: fork, in: size)
                let angle = partnerAngle(t: partnerNodeT(index), fork: fork, in: size)
                partnerGlyph(node.state, below: index.isMultiple(of: 2), angle: angle)
                    .position(point)
            }
        }
        // The partner is a passive lateral — it never receives focus taps (the
        // "& partner" name line is the manual focus switch, DESIGN.md §5.4).
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func partnerGlyph(_ state: BranchNodeState, below: Bool, angle: Angle) -> some View {
        let pigment = palette.supersetPartnerBranch
        switch state {
        case .leaf:
            partnerBlade(.inked(fill: pigment, rib: nil), below: below, angle: angle)
        case .dashedLeaf:
            partnerBlade(.dashed(pigment), below: below, angle: angle)
        case .future:
            partnerBlade(
                .ghost(pigment.opacity(0.55)),
                below: below,
                angle: angle,
                length: PartnerMetrics.leafLength * Metrics.ghostScale
            )
        case .bud:
            // The partner never carries the active blade; the seam demotes it to a future.
            EmptyView()
        }
    }

    /// The partner's blades speak the focused stem's vocabulary at a smaller
    /// scale, with the tilt sides mirrored for the drooping lateral.
    private func partnerBlade(
        _ style: BranchBladeGlyph.Style,
        below: Bool,
        angle: Angle,
        length: CGFloat = PartnerMetrics.leafLength
    ) -> some View {
        let size = CGSize(width: length, height: length * LeafShape.aspectRatio)
        let tilt = Angle(degrees: below ? Metrics.leafTiltBelow : -Metrics.leafTiltAbove)
        return BranchBladeGlyph(style: style, size: size)
            .offset(x: size.width / 2)
            .rotationEffect(angle + tilt)
    }

    private func partnerTip(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * PartnerMetrics.endX, y: size.height * PartnerMetrics.endY)
    }

    private func partnerControl(fork: CGPoint, in size: CGSize) -> CGPoint {
        let tip = partnerTip(in: size)
        return CGPoint(x: (fork.x + tip.x) / 2, y: (fork.y + tip.y) / 2 + PartnerMetrics.droop)
    }

    private func partnerNodeT(_ index: Int) -> CGFloat {
        BranchNodeLayout.nodeT(
            index: index,
            count: partnerNodes.count,
            first: PartnerMetrics.firstNodeT,
            last: PartnerMetrics.lastNodeT,
            maxStep: PartnerMetrics.maxNodeStep
        )
    }

    private func partnerCurve(fork: CGPoint, in size: CGSize) -> QuadraticBezier {
        QuadraticBezier(start: fork, control: partnerControl(fork: fork, in: size), end: partnerTip(in: size))
    }

    private func partnerPoint(t: CGFloat, fork: CGPoint, in size: CGSize) -> CGPoint {
        partnerCurve(fork: fork, in: size).point(at: t)
    }

    private func partnerAngle(t: CGFloat, fork: CGPoint, in size: CGSize) -> Angle {
        let tangent = partnerCurve(fork: fork, in: size).tangent(at: t)
        return Angle(radians: atan2(tangent.dy, tangent.dx))
    }

    // MARK: - Stem geometry

    private func nodeT(_ index: Int) -> CGFloat {
        BranchNodeLayout.nodeT(
            index: index,
            count: nodes.count,
            first: Metrics.firstNodeT,
            last: Metrics.lastNodeT,
            maxStep: Metrics.maxNodeStep
        )
    }

    /// The climbing stem as a quadratic bezier bowed gently upward: root at low
    /// leading, tip at high trailing.
    private func stemCurve(in size: CGSize) -> QuadraticBezier {
        let p0 = CGPoint(x: Metrics.leadInset, y: size.height * Metrics.rootY)
        let p1 = CGPoint(x: size.width - Metrics.trailInset, y: size.height * Metrics.tipY)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - Metrics.bow)
        return QuadraticBezier(start: p0, control: control, end: p1)
    }

    /// A point on the climbing stem at parameter `t`.
    private func stemPoint(t: CGFloat, in size: CGSize) -> CGPoint {
        stemCurve(in: size).point(at: t)
    }

    /// The stem's tangent angle at parameter `t`, so leaves and future strokes
    /// align with the climb.
    private func stemAngle(t: CGFloat, in size: CGSize) -> Angle {
        let tangent = stemCurve(in: size).tangent(at: t)
        return Angle(radians: atan2(tangent.dy, tangent.dx))
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

/// The Superset partner's drooping lateral — a quadratic bezier forking off the
/// focused stem and bowing downward, so the partner reads as a subordinate branch
/// of one plant rather than a second climbing stem (DESIGN.md §5.4).
private struct LateralPath: Shape {
    let fork: CGPoint
    let tip: CGPoint
    let droop: CGFloat

    func path(in rect: CGRect) -> Path {
        let control = CGPoint(x: (fork.x + tip.x) / 2, y: (fork.y + tip.y) / 2 + droop)
        var path = Path()
        path.move(to: fork)
        path.addQuadCurve(to: tip, control: control)
        return path
    }
}

/// Every branch mark is this one blade in a different dress (the verdict on
/// `docs/prototypes/branch-low-set-prototype.html`, matching pick
/// session-stage-a): inked with a cream rib for a Logged Set, a dashed outline
/// for a Skipped Set, cream-filled inside a green stroke for the active Set
/// (`glow` lights it at Night and is `nil` by Day), and a faint ghost outline
/// for a Pending Set.
private struct BranchBladeGlyph: View {
    enum Style {
        case inked(fill: Color, rib: Color?)
        case dashed(Color)
        case cream(fill: Color, stroke: Color, glow: Color?)
        case ghost(Color)
    }

    let style: Style
    let size: CGSize

    var body: some View {
        Group {
            switch style {
            case .inked(let fill, let rib):
                ZStack {
                    LeafShape().fill(fill)
                    if let rib {
                        RibShape().stroke(rib, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }
                }
            case .dashed(let stroke):
                LeafShape().stroke(
                    stroke,
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 4])
                )
            case .cream(let fill, let stroke, let glow):
                ZStack {
                    LeafShape().fill(fill)
                    LeafShape().stroke(stroke, lineWidth: 1.8)
                }
                .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 7)
            case .ghost(let stroke):
                LeafShape().stroke(stroke, lineWidth: 1.4)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The blade silhouette (`M0,10 C16,-2 46,-4 64,3 C44,16 14,19 0,10 Z`) in a
/// 64×20 design space — slender and pointed both ends, base at the leading
/// mid-height so a half-width pre-rotation offset anchors it on the stem —
/// scaled into the drawing rect. Matches pick session-stage-a; replaces the
/// retired 60×24 rounded leaf.
struct LeafShape: Shape {
    /// height / width of the design space, for callers sizing a frame off one length.
    static let aspectRatio: CGFloat = 20.0 / 64.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addCurve(to: CGPoint(x: 64, y: 3), control1: CGPoint(x: 16, y: -2), control2: CGPoint(x: 46, y: -4))
        path.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: 44, y: 16), control2: CGPoint(x: 14, y: 19))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 64, y: rect.height / 20))
    }
}

/// The blade's cream rib streak (`M7,8.6 C24,4.6 42,2.6 56,3.4`), just off the
/// spine, in the same 64×20 space.
struct RibShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 7, y: 8.6))
        path.addCurve(to: CGPoint(x: 56, y: 3.4), control1: CGPoint(x: 24, y: 4.6), control2: CGPoint(x: 42, y: 2.6))
        return path.applying(CGAffineTransform(scaleX: rect.width / 64, y: rect.height / 20))
    }
}
