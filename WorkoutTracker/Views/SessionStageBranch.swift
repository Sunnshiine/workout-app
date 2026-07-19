import SwiftUI

/// Shared branch-flora geometry (token sheet §Stage & branch). The single stem and
/// the Superset fork draw the same leaf/bud/future glyphs — only the pigment
/// (focus vs subordinated partner) differs — so the shapes live here once and take
/// their colors from the caller. The leaf's design space is 60×24 with the stem
/// crossing at y≈8; display scale `s` sets the stroke widths (rib 1.2/s, bud 2.2/s,
/// future/skip 1.2/s).
private enum BranchGeometry {
    static let nodeWidth: CGFloat = 30
    static let nodeHeight: CGFloat = 46
    static let scale: CGFloat = 0.5
    static var leafLift: CGFloat { nodeHeight / 5 }
    static var leafSize: CGSize {
        CGSize(width: nodeWidth * 0.92, height: nodeWidth * 0.92 * (24.0 / 60.0) * 2.2)
    }
    static var strokeWidth: CGFloat { 1.2 * scale }
}

/// One leaf: an inked silhouette (with an optional cream rib) for a Logged Set, or
/// a dashed outline for a Skipped Set. `rib == nil` drops the rib so a subordinated
/// partner leaf reads flatter than the focused branch's.
private struct BranchLeafGlyph: View {
    let filled: Bool
    let fill: Color
    let rib: Color?
    let dash: Color

    var body: some View {
        ZStack {
            if filled {
                LeafShape().fill(fill)
                if let rib {
                    RibShape().stroke(rib, style: StrokeStyle(lineWidth: BranchGeometry.strokeWidth, lineCap: .round))
                }
            } else {
                LeafShape().stroke(
                    dash,
                    style: StrokeStyle(lineWidth: BranchGeometry.strokeWidth, lineCap: .round, dash: [5, 4])
                )
            }
        }
        .frame(width: BranchGeometry.leafSize.width, height: BranchGeometry.leafSize.height)
    }
}

/// The active Set's cream bud with a green stroke; `glow` lights it at Night and is
/// `nil` (unlit) by Day.
private struct BranchBudGlyph: View {
    let fill: Color
    let stroke: Color
    let glow: Color?

    var body: some View {
        let diameter = BranchGeometry.nodeWidth * 0.5
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(stroke, lineWidth: 2.2 * BranchGeometry.scale))
            .frame(width: diameter, height: diameter)
            .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 7)
    }
}

/// A faint future stroke for a Pending Set still ahead.
private struct BranchFutureGlyph: View {
    let stroke: Color

    var body: some View {
        Circle()
            .strokeBorder(stroke, lineWidth: BranchGeometry.strokeWidth)
            .frame(width: BranchGeometry.nodeWidth * 0.34, height: BranchGeometry.nodeWidth * 0.34)
    }
}

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

    private var nodes: [(set: ExerciseSet, state: BranchNodeState)] {
        Array(zip(sets, SessionStagePresentation.branchNodeStates(for: sets, activeSetID: activeSetID)))
    }

    var body: some View {
        ZStack {
            stem
            HStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.set.persistentModelID) { index, node in
                    nodeCell(node.set, state: node.state, above: index.isMultiple(of: 2))
                        .frame(width: BranchGeometry.nodeWidth, height: BranchGeometry.nodeHeight)
                }
            }
        }
        .frame(height: BranchGeometry.nodeHeight)
        .animation(reduceMotion ? nil : Theme.wingAnimation(duration: Theme.Motion.leafInk), value: activeSetID)
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
    }

    // The 2px round-cap stem runs the branch's width, sitting on the leaf baseline.
    private var stem: some View {
        Capsule()
            .fill(palette.stem)
            .frame(height: 2)
            .padding(.horizontal, BranchGeometry.nodeWidth / 2)
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
            leaf(filled: true).offset(y: above ? -BranchGeometry.leafLift : BranchGeometry.leafLift)
        case .dashedLeaf:
            leaf(filled: false).offset(y: above ? -BranchGeometry.leafLift : BranchGeometry.leafLift)
        case .bud:
            BranchBudGlyph(fill: palette.budFill, stroke: palette.budStroke, glow: palette.budGlow)
        case .future:
            BranchFutureGlyph(stroke: palette.futureStroke)
        }
    }

    private func leaf(filled: Bool) -> some View {
        BranchLeafGlyph(filled: filled, fill: palette.leafFill, rib: palette.leafRib, dash: palette.skipStroke)
    }
}

/// A Superset drawn as one forked stem — still the page's one icon. The focused
/// Exercise's branch leads at full stroke and alone carries the bud; the partner
/// is a shorter drooping lateral (1.6px) that subordinates by pigment by Day and
/// by translucency at Night (both routed through `palette.supersetPartnerBranch`).
/// Node states come from `SessionStagePresentation.supersetFork`, so alternation
/// is one bud settling and one waking — never a branch redraw — and this view
/// owns geometry only.
struct SupersetForkBranch: View {
    let fork: SupersetForkPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let focused = fork.focusedBranch {
                ForkBranchRow(states: focused.nodeStates, isFocused: true)
            }
            if let partner = fork.partnerBranch {
                // The partner branch forks off the leading stem and droops.
                ForkBranchRow(states: partner.nodeStates, isFocused: false)
                    .padding(.leading, BranchGeometry.nodeWidth * 0.6)
                    .rotationEffect(.degrees(4), anchor: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : Theme.wingAnimation(duration: Theme.Motion.leafInk), value: fork)
        // The plain `Set N of M` head and the "& partner" name line carry the
        // reading in words; the fork stays a textless glyph.
        .accessibilityHidden(true)
    }
}

/// One branch of the forked stem. The focused branch renders in full stage
/// pigment with the bud and rib; the partner subordinates to
/// `supersetPartnerBranch`, thins to 1.6px, drops the rib, and never buds.
private struct ForkBranchRow: View {
    let states: [BranchNodeState]
    let isFocused: Bool
    @Environment(\.themePalette) private var palette

    private var branchColor: Color { isFocused ? palette.stem : palette.supersetPartnerBranch }
    private var stemWidth: CGFloat { isFocused ? 2 : 1.6 }

    var body: some View {
        ZStack {
            Capsule()
                .fill(branchColor)
                .frame(height: stemWidth)
                .padding(.horizontal, BranchGeometry.nodeWidth / 2)

            HStack(spacing: 0) {
                ForEach(Array(states.enumerated()), id: \.offset) { index, state in
                    glyph(state, above: index.isMultiple(of: 2))
                        .frame(width: BranchGeometry.nodeWidth, height: BranchGeometry.nodeHeight)
                }
            }
        }
        .frame(height: BranchGeometry.nodeHeight)
    }

    @ViewBuilder
    private func glyph(_ state: BranchNodeState, above: Bool) -> some View {
        switch state {
        case .leaf:
            leaf(filled: true).offset(y: above ? -BranchGeometry.leafLift : BranchGeometry.leafLift)
        case .dashedLeaf:
            leaf(filled: false).offset(y: above ? -BranchGeometry.leafLift : BranchGeometry.leafLift)
        case .bud:
            // Only the focused branch ever buds; the partner's Pending Sets stay futures.
            if isFocused {
                BranchBudGlyph(fill: palette.budFill, stroke: palette.budStroke, glow: palette.budGlow)
            } else {
                BranchFutureGlyph(stroke: branchColor)
            }
        case .future:
            BranchFutureGlyph(stroke: branchColor)
        }
    }

    private func leaf(filled: Bool) -> some View {
        // The partner subordinates by pigment: it fills in the partner tone, drops
        // the cream rib, and dashes in that same tone rather than the skip stroke.
        BranchLeafGlyph(
            filled: filled,
            fill: isFocused ? palette.leafFill : palette.supersetPartnerBranch,
            rib: isFocused ? palette.leafRib : nil,
            dash: isFocused ? palette.skipStroke : palette.supersetPartnerBranch
        )
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
