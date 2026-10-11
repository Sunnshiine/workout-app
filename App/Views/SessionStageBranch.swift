import SwiftUI

struct SessionStageBranch: View {
    private let stem: [BranchNode]
    private let lateral: [BranchNode]?
    private let focusedArm: BranchArm
    private let activeSetID: ActiveSetID?
    /// A Superset's fork takes no tap, so its branch stays a passive glyph.
    private let onTap: ((ExerciseSet) -> Void)?
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Metrics {
        static let minimumHeight: CGFloat = 70
        static let fullHeight: CGFloat = 156
        static let leadInset: CGFloat = 24
        static let trailInset: CGFloat = 28
        static let rootY: CGFloat = 0.82 // fraction of height — the low leading root
        static let tipInset: CGFloat = fullHeight * 0.13
        static let bow: CGFloat = 30
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

    private enum LateralMetrics {
        static let stemWidth: CGFloat = 1.6
        static let forkOnStemT: CGFloat = 0.30
        static let endX: CGFloat = 0.62 // fraction of width for the drooping tip
        static let endY: CGFloat = 0.99 // fraction of height — the tip droops low
        static let droop: CGFloat = 30
        static let firstNodeT: CGFloat = 0.42
        static let lastNodeT: CGFloat = 0.9
        static let maxNodeStep: CGFloat = 0.2
        static let leafLength: CGFloat = 34
        static let inkBelowDrawing: CGFloat = 28
        static let clearance: CGFloat = 2
    }

    init(branch: StageBranch, onTap: @escaping (ExerciseSet) -> Void) {
        stem = branch.nodes
        lateral = nil
        focusedArm = .stem
        activeSetID = branch.activeSetID
        self.onTap = onTap
    }

    init(fork: ForkedBranch) {
        stem = fork.stem
        lateral = fork.lateral
        focusedArm = fork.focusedArm
        activeSetID = fork.activeSetID
        onTap = nil
    }

    var body: some View {
        GeometryReader { geo in
            let drawing = CGSize(width: geo.size.width, height: min(geo.size.height, Metrics.fullHeight))
            ZStack {
                if let lateral {
                    lateralBranch(
                        lateral,
                        in: drawing,
                        room: geo.size.height - drawing.height + Theme.stageColumnSpacing - LateralMetrics.clearance
                    )
                }

                CurvePath(curve: stemCurve(in: drawing))
                    .stroke(pigment(.stem, focused: palette.stem), style: StrokeStyle(lineWidth: Metrics.stemWidth, lineCap: .round))

                ForEach(Array(stem.enumerated()), id: \.element.set.persistentModelID) { index, node in
                    let point = stemPoint(t: nodeT(index), in: drawing)
                    let angle = stemAngle(t: nodeT(index), in: drawing)
                    nodeCell(node.set, glyph: glyph(node.state, on: .stem, index: index, angle: angle, leafLength: Metrics.leafLength))
                        .position(point)
                }
            }
            // A node leaving or joining mid-ink keeps the frame it had when it left or joined. Grouped,
            // that frame is the branch's, so it rides the stem when the stage slides under it. Outside the
            // reader, the group would round the size the reader measures and hang the lateral past its room.
            .geometryGroup()
        }
        .frame(minHeight: Metrics.minimumHeight, idealHeight: Metrics.minimumHeight, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .animation(Theme.branchAnimation(.leafInk, reducingMotion: reduceMotion), value: activeSetID)
        .animation(Theme.branchAnimation(.relayout, reducingMotion: reduceMotion), value: [stem.count, lateral?.count ?? 0])
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
    }

    // MARK: - Nodes

    @ViewBuilder
    private func nodeCell(_ set: ExerciseSet, glyph: some View) -> some View {
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
    private func glyph(
        _ state: BranchNodeState,
        on arm: BranchArm,
        index: Int,
        angle: Angle,
        leafLength: CGFloat
    ) -> some View {
        let focused = arm == focusedArm
        let leansUp = index.isMultiple(of: 2) == (arm == .stem)
        let tilt = Angle(degrees: leansUp ? -Metrics.leafTiltAbove : Metrics.leafTiltBelow)
        let blade = { (style: BranchBladeGlyph.Style, length: CGFloat) in
            let size = CGSize(width: length, height: length * LeafShape.aspectRatio)
            return BranchBladeGlyph(style: style, size: size, angle: angle + tilt)
        }
        switch state {
        case .leaf:
            blade(.inked(fill: pigment(arm, focused: palette.leafFill), rib: focused ? palette.leafRib : nil), leafLength)
        case .dashedLeaf:
            blade(.dashed(pigment(arm, focused: palette.skipStroke)), leafLength)
        case .bud:
            blade(.cream(fill: palette.budFill, stroke: palette.budStroke, glow: palette.budGlow), leafLength)
                .transition(budTransition)
        case .future:
            blade(
                .ghost(focused ? palette.futureStroke : palette.supersetPartnerBranch.opacity(0.55)),
                leafLength * Metrics.ghostScale
            )
        }
    }

    /// The bud wakes on its own delay, which only an animation the transition carries can run; an
    /// `.animation` keyed on the branch would wake it with the leaf.
    private var budTransition: AnyTransition {
        let wake: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity)
        return .asymmetric(
            insertion: wake.animation(Theme.branchAnimation(.budWake, reducingMotion: reduceMotion)),
            // A Superset dissolves once either side has no Pending Set, so every bud move on a fork
            // crosses arms; the old bud leaves at once so no frame shows two cream leaves.
            removal: lateral == nil ? wake : .identity
        )
    }

    private func pigment(_ arm: BranchArm, focused: Color) -> Color {
        arm == focusedArm ? focused : palette.supersetPartnerBranch
    }

    @ViewBuilder
    private func lateralBranch(_ lateralNodes: [BranchNode], in size: CGSize, room: CGFloat) -> some View {
        let scale = min(heightScale(size), room / LateralMetrics.inkBelowDrawing)
        let curve = lateralCurve(in: size, droop: LateralMetrics.droop * scale)
        ZStack {
            CurvePath(curve: curve)
                .stroke(
                    pigment(.lateral, focused: palette.stem),
                    style: StrokeStyle(lineWidth: LateralMetrics.stemWidth, lineCap: .round)
                )

            ForEach(Array(lateralNodes.enumerated()), id: \.element.set.persistentModelID) { index, node in
                let t = lateralNodeT(index, count: lateralNodes.count)
                let tangent = curve.tangent(at: t)
                glyph(
                    node.state,
                    on: .lateral,
                    index: index,
                    angle: Angle(radians: atan2(tangent.dy, tangent.dx)),
                    leafLength: LateralMetrics.leafLength * scale
                )
                .position(curve.point(at: t))
            }
        }
    }

    private func lateralNodeT(_ index: Int, count: Int) -> CGFloat {
        BranchNodeLayout.nodeT(
            index: index,
            count: count,
            first: LateralMetrics.firstNodeT,
            last: LateralMetrics.lastNodeT,
            maxStep: LateralMetrics.maxNodeStep
        )
    }

    private func lateralCurve(in size: CGSize, droop: CGFloat) -> QuadraticBezier {
        let fork = stemPoint(t: LateralMetrics.forkOnStemT, in: size)
        let tip = CGPoint(x: size.width * LateralMetrics.endX, y: size.height * LateralMetrics.endY)
        let control = CGPoint(x: (fork.x + tip.x) / 2, y: (fork.y + tip.y) / 2 + droop)
        return QuadraticBezier(start: fork, control: control, end: tip)
    }

    // MARK: - Stem geometry

    private func nodeT(_ index: Int) -> CGFloat {
        BranchNodeLayout.nodeT(
            index: index,
            count: stem.count,
            first: Metrics.firstNodeT,
            last: Metrics.lastNodeT,
            maxStep: Metrics.maxNodeStep
        )
    }

    /// The climbing stem as a quadratic bezier bowed gently upward: root at low
    /// leading, tip at high trailing.
    private func stemCurve(in size: CGSize) -> QuadraticBezier {
        let p0 = CGPoint(x: Metrics.leadInset, y: size.height * Metrics.rootY)
        let p1 = CGPoint(x: size.width - Metrics.trailInset, y: Metrics.tipInset)
        let control = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - Metrics.bow * heightScale(size))
        return QuadraticBezier(start: p0, control: control, end: p1)
    }

    private func heightScale(_ size: CGSize) -> CGFloat {
        size.height / Metrics.fullHeight
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

private struct CurvePath: Shape {
    var curve: QuadraticBezier

    typealias AnimatableData = AnimatablePair<
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, CGPoint.AnimatableData
    >

    nonisolated var animatableData: AnimatableData {
        get {
            AnimatablePair(
                AnimatablePair(curve.start.animatableData, curve.control.animatableData),
                curve.end.animatableData
            )
        }
        set {
            var start = CGPoint.zero
            var control = CGPoint.zero
            var end = CGPoint.zero
            start.animatableData = newValue.first.first
            control.animatableData = newValue.first.second
            end.animatableData = newValue.second
            curve = QuadraticBezier(start: start, control: control, end: end)
        }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: curve.start)
        path.addQuadCurve(to: curve.end, control: curve.control)
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
    let angle: Angle

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
        .offset(x: size.width / 2)
        .rotationEffect(angle)
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
