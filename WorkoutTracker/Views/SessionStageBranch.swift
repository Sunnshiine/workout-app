import SwiftUI

/// The living stage's branch — the page's one icon and its only piece of flora.
/// A round-cap stem carries one inked leaf per Logged Set, a dashed-outline leaf
/// per Skipped Set, a cream bud with a green stroke for the active Set (carrying
/// the page's one glow at Night), and faint future strokes for what remains. The
/// branch stands textless; the plain `Set N of M` head carries the reading in
/// words. Node states derive from `SessionStagePresentation.branchNodeStates`, so
/// the branch owns geometry only — never Set-State interpretation.
struct SessionStageBranch: View {
    let sets: [ExerciseSet]
    var activeSetID: ActiveSetID?
    /// Tapping a node focuses its Set — matching the retired dots' behavior. `nil`
    /// keeps the branch a passive glyph (e.g. a queue-row summary).
    var onTap: ((ExerciseSet) -> Void)?
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Geometry constants (token sheet §Stage & branch) — not palette. The leaf's
    // design space is 60×24 with the stem crossing at y≈8; display scale `s` sets
    // the stroke widths (rib 1.2/s, bud 2.2/s, future/skip 1.2/s).
    private let nodeWidth: CGFloat = 30
    private let nodeHeight: CGFloat = 46
    private let scale: CGFloat = 0.5

    private var nodes: [(set: ExerciseSet, state: BranchNodeState)] {
        Array(zip(sets, SessionStagePresentation.branchNodeStates(for: sets, activeSetID: activeSetID)))
    }

    var body: some View {
        ZStack {
            stem
            HStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.set.persistentModelID) { index, node in
                    nodeCell(node.set, state: node.state, above: index.isMultiple(of: 2))
                        .frame(width: nodeWidth, height: nodeHeight)
                }
            }
        }
        .frame(height: nodeHeight)
        .animation(reduceMotion ? nil : Theme.wingAnimation(duration: Theme.Motion.leafInk), value: activeSetID)
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
    }

    // The 2px round-cap stem runs the branch's width, sitting on the leaf baseline.
    private var stem: some View {
        Capsule()
            .fill(palette.stem)
            .frame(height: 2)
            .padding(.horizontal, nodeWidth / 2)
    }

    @ViewBuilder
    private func nodeCell(_ set: ExerciseSet, state: BranchNodeState, above: Bool) -> some View {
        let glyph = nodeGlyph(state, above: above)
        if let onTap {
            Button {
                onTap(set)
            } label: {
                glyph.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(set.index + 1), \(SetRowPresentation(set: set).title)")
        } else {
            glyph
        }
    }

    @ViewBuilder
    private func nodeGlyph(_ state: BranchNodeState, above: Bool) -> some View {
        switch state {
        case .leaf:
            leaf(filled: true).offset(y: above ? -leafLift : leafLift)
        case .dashedLeaf:
            leaf(filled: false).offset(y: above ? -leafLift : leafLift)
        case .bud:
            bud
        case .future:
            futureStroke
        }
    }

    private var leafLift: CGFloat { nodeHeight / 5 }

    @ViewBuilder
    private func leaf(filled: Bool) -> some View {
        let size = CGSize(width: nodeWidth * 0.92, height: nodeWidth * 0.92 * (24.0 / 60.0) * 2.2)
        ZStack {
            if filled {
                LeafShape().fill(palette.leafFill)
                RibShape().stroke(palette.leafRib, style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
            } else {
                LeafShape().stroke(
                    palette.skipStroke,
                    style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round, dash: [5, 4])
                )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var bud: some View {
        let diameter = nodeWidth * 0.5
        return Circle()
            .fill(palette.budFill)
            .overlay(Circle().strokeBorder(palette.budStroke, lineWidth: 2.2 * scale))
            .frame(width: diameter, height: diameter)
            .shadow(color: palette.budGlow ?? .clear, radius: palette.budGlow == nil ? 0 : 7)
    }

    private var futureStroke: some View {
        Circle()
            .strokeBorder(palette.futureStroke, lineWidth: 1.2 * scale)
            .frame(width: nodeWidth * 0.34, height: nodeWidth * 0.34)
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
