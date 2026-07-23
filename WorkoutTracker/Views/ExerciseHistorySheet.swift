import SwiftUI

/// The Exercise History sheet (`DESIGN.md` §5.6 — the chip ledger): a `.medium` detent opened only
/// from the Last Performed line, showing the last ~5 entries for the viewed Exercise's Movement as
/// calm reference material. Living-paper fill and `soft` shoulders keep it in the same room; every
/// Set is a **carved chip** — the app's only below-flat elevation, cut into the sheet under a dark
/// top inner shadow with a light bottom edge (ledger §7.1) — flowing off a `Wn Dn` gutter under
/// quiet muted sentence-case Block headers (ledger §7.4), newest first.
///
/// Skips, Legacy Log rawness, and fallback-spelling annotations never sit in the ledger: they hide
/// behind a `*` on the W/D label that expands into a small carved well. A fully-unparseable entry
/// still carries its `*` well — the raw Sheet line inside it — so a row never renders chipless
/// (re-drive addendum §7.5). A Volume control (off by default, raised at rest on the cream recipe,
/// pressed below flat when active) summons the one chart — total volume per Session, hollow `≈`
/// dots where Legacy Logs make totals approximate, a dotted Block seam — never pushed.
struct ExerciseHistorySheet: View {
    let presentation: ExerciseHistorySheetPresentation
    /// The fill-in-progress affordance, present only while history for this Movement may still
    /// deepen (sub-issue #366). `nil` once the fill has reached coverage or exhausted the tabs.
    var fillProgress: HistoryFillProgressPresentation?

    @Environment(\.themePalette) private var palette
    @State private var showVolume: Bool
    @State private var expandedWells: Set<String> = []

    init(
        presentation: ExerciseHistorySheetPresentation,
        fillProgress: HistoryFillProgressPresentation? = nil,
        showVolume: Bool = false
    ) {
        self.presentation = presentation
        self.fillProgress = fillProgress
        _showVolume = State(initialValue: showVolume)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // Scoped to the viewed Movement: a fill may be running for other Movements, but the
                // affordance only shows while *this* Movement's history could still deepen (PRD #357 §4).
                if let fillProgress, presentation.mayStillDeepen {
                    fillAffordance(fillProgress)
                }

                if presentation.isEmpty {
                    // While the fill is still reaching for this Movement, stay quiet rather than
                    // claiming there is no history — the affordance already speaks for it.
                    if fillProgress == nil {
                        Text("No history yet")
                            .font(.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                } else {
                    if showVolume {
                        volumeChart
                    }
                    ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { _, block in
                        blockSection(block)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.soft)
        .presentationBackground { palette.paperBackground }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(Theme.font(.sheetTitle))
                    .foregroundStyle(palette.textPrimary)
                Text(presentation.subtitle)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 12)

            // Trend reading is available but never pushed: off by default, and only worth offering
            // once there is a total to plot.
            if !presentation.volumePoints.isEmpty {
                volumeControl
            }
        }
    }

    /// The Volume control — a chip-vocabulary pill. At rest it sits *raised* on the cream recipe
    /// (`volumeControlRaisedFill` over the `cardLow` lift); when active it presses below flat into the
    /// carved-chip recipe (ledger §7.2). No action green.
    private var volumeControl: some View {
        Button {
            showVolume.toggle()
        } label: {
            Text("Volume")
                .font(Theme.font(.queuePill))
                .foregroundStyle(showVolume ? palette.textPrimary : palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if showVolume {
                        Color.clear.themeCarve(palette, in: Capsule())
                    } else {
                        Capsule()
                            .fill(Theme.LightKit.volumeControlRaisedFill)
                            .themeElevation(Theme.LightKit.volumeControlRaisedShadow, in: Capsule())
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history-volume-toggle")
        .accessibilityLabel("Volume")
        .accessibilityValue(showVolume ? "on" : "off")
    }

    /// A visible, playful fill affordance in the product's warm voice: a warm line, a muted
    /// determinate bar, and an honest per-tab detail — never mint, never a dead spinner (revised
    /// `DESIGN.md`). Existing entries stay readable beneath it; it never blocks the list.
    private func fillAffordance(_ progress: HistoryFillProgressPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress.message)
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
            ProgressView(value: progress.fraction)
                .tint(palette.textSecondary)
            Text(progress.detail)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-fill-progress")
    }

    private var volumeChart: some View {
        VolumeChart(points: presentation.volumePoints, seamIndices: presentation.volumeBlockSeamIndices)
            .environment(\.themePalette, palette)
    }

    private func blockSection(_ block: ExerciseHistorySheetPresentation.Block) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // A quiet muted sentence-case Block header (`Block 27`) — no rule, no uppercase editorial
            // scaffolding; the pick's calm register (ledger §7.4).
            Text(block.header)
                .font(Theme.font(.queuePill))
                .foregroundStyle(palette.textSecondary)

            ForEach(Array(block.rows.enumerated()), id: \.offset) { index, row in
                let key = "\(block.header)/\(index)/\(row.gutter)"
                ExerciseHistoryRow(
                    row: row,
                    isWellExpanded: expandedWells.contains(key),
                    onToggleWell: { toggle(key) }
                )
            }
        }
    }

    private func toggle(_ key: String) {
        if expandedWells.contains(key) {
            expandedWells.remove(key)
        } else {
            expandedWells.insert(key)
        }
    }
}

/// One entry: a `Wn Dn` gutter (with the entry's Cadence beneath) carrying a `*` when it has a well,
/// then its Sets as carved chips that flow to a second line — chips wrap; text never wraps
/// (DESIGN.md §5.6). The `*` toggles a small carved well of the hidden annotations.
private struct ExerciseHistoryRow: View {
    let row: ExerciseHistorySheetPresentation.Row
    let isWellExpanded: Bool
    let onToggleWell: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                gutterLabel
                    .frame(width: 52, alignment: .leading)

                ChipFlowLayout(spacing: 6) {
                    ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                        chipView(chip)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if row.hasWell, isWellExpanded {
                well
                    .padding(.leading, 64)
            }
        }
    }

    private var gutterLabel: some View {
        Button(action: onToggleWell) {
            VStack(alignment: .leading, spacing: 1) {
                (Text(row.gutter) + wellMarker)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textPrimary)
                if let cadence = row.cadence {
                    Text(cadence)
                        .font(Theme.font(.cadence))
                        .foregroundStyle(palette.textSecondary.opacity(0.75))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.hasWell)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.hasWell ? "Shows skipped Sets and notes" : "")
    }

    private var wellMarker: Text {
        guard row.hasWell else { return Text("") }
        return Text(" *").foregroundColor(palette.textSecondary)
    }

    private func chipView(_ chip: ExerciseHistorySheetPresentation.Chip) -> some View {
        HStack(spacing: 3) {
            Text(chip.load)
                .foregroundStyle(palette.textPrimary)
            if let rpe = chip.rpe {
                Text("@\(rpe)")
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .font(Theme.font(.historyChip))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // Carved: the app's only below-flat elevation — a dark top inner shadow and a light bottom
        // edge press the chip into the sheet, never a raised highlight (ledger §7.1).
        .themeCarve(palette, in: Capsule())
    }

    /// The carved well: the row's hidden annotations, spelled quietly. Skips, Legacy Log rawness,
    /// and fallback spelling all live here so the ledger stays calm until asked.
    private var well: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(row.annotations.enumerated()), id: \.offset) { _, annotation in
                annotationLine(annotation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .themeCarve(palette, in: RoundedRectangle(cornerRadius: Theme.Radius.cell))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-well")
    }

    private func annotationLine(_ annotation: ExerciseHistorySheetPresentation.Annotation) -> some View {
        Text(annotationText(annotation))
            .font(.footnote)
            .italic()
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func annotationText(_ annotation: ExerciseHistorySheetPresentation.Annotation) -> String {
        switch annotation {
        case .asName(let name):
            return "as “\(name)”"
        case .skipped(let count):
            return count == 1 ? "1 Set skipped" : "\(count) Sets skipped"
        case .asEntered(let raw):
            return "“\(raw)”"
        }
    }
}

// MARK: - Volume chart

/// The one chart, athlete-summoned and off by default (DESIGN.md §5.6): total volume per Session as
/// a quiet ink line, solid ink dots with a paper core for exact totals, hollow `≈` dots where Legacy
/// Logs make a total best-effort, and a dotted seam wherever the line crosses a Block boundary. No
/// axes, no labels — history is reference reading, not a dashboard (The History Is Reference Rule).
private struct VolumeChart: View {
    let points: [ExerciseHistorySheetPresentation.VolumePoint]
    /// Block-boundary indices, derived at the presentation seam so the view owns geometry only.
    let seamIndices: [Int]

    @Environment(\.themePalette) private var palette

    private let inset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let positions = positions(in: geo.size)
            ZStack {
                blockSeams(positions: positions, height: geo.size.height)
                inkLine(positions: positions)
                dots(positions: positions)
            }
        }
        .frame(height: 96)
        .accessibilityElement()
        .accessibilityLabel("Total volume chart")
        .accessibilityIdentifier("history-volume-chart")
    }

    /// Even x-spacing; y mapped into the padded plot from the volume range. A flat or single-point
    /// series sits on the vertical centre so it reads as calm rather than pinned to an edge.
    private func positions(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let volumes = points.map(\.volume)
        let minV = volumes.min() ?? 0
        let maxV = volumes.max() ?? 0
        let span = maxV - minV

        let plotWidth = size.width - inset * 2
        let plotHeight = size.height - inset * 2

        return points.enumerated().map { index, point in
            let x: CGFloat
            if points.count == 1 {
                x = size.width / 2
            } else {
                x = inset + plotWidth * CGFloat(index) / CGFloat(points.count - 1)
            }
            let y: CGFloat
            if span == 0 {
                y = size.height / 2
            } else {
                // Higher volume sits higher on the plot.
                y = inset + plotHeight * (1 - CGFloat((point.volume - minV) / span))
            }
            return CGPoint(x: x, y: y)
        }
    }

    private func inkLine(positions: [CGPoint]) -> some View {
        Path { path in
            for (index, position) in positions.enumerated() {
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
        .stroke(palette.chartLine, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func blockSeams(positions: [CGPoint], height: CGFloat) -> some View {
        ForEach(seamIndices, id: \.self) { index in
            let seamX = (positions[index - 1].x + positions[index].x) / 2
            Path { path in
                path.move(to: CGPoint(x: seamX, y: 0))
                path.addLine(to: CGPoint(x: seamX, y: height))
            }
            // Dotted `1 4`, not dashed — the quiet seam of the token sheet (ledger §7.3).
            .stroke(palette.blockSeam, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 4]))
        }
    }

    private func dots(positions: [CGPoint]) -> some View {
        ForEach(points.indices, id: \.self) { index in
            dot(points[index].approximate ? Theme.LightKit.approxDot : Theme.LightKit.dataDot)
                .position(positions[index])
        }
    }

    /// A plotted point. The exact dot is a solid ink disc with a punched paper core (it reads as a
    /// filled dot lifting off the paper); the approximate `≈` dot is a hollow ink outline (ledger §7.3).
    private func dot(_ spec: Theme.DotSpec) -> some View {
        ZStack {
            if spec.lineWidth > 0 {
                Circle()
                    .strokeBorder(palette.chartLine, lineWidth: spec.lineWidth)
            } else {
                Circle()
                    .fill(spec.color)
            }
            if spec.hasPaperCore {
                Circle()
                    .fill(palette.sheetFill)
                    .frame(width: spec.radius, height: spec.radius)
            }
        }
        .frame(width: spec.radius * 2, height: spec.radius * 2)
    }
}

// MARK: - Chip flow

/// A minimal wrapping layout so carved chips flow to a second line when the row runs out of width
/// (DESIGN.md §5.6 "chips may flow to a second line"). No horizontal scrolling — the ledger reads
/// top-to-bottom.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: min(maxWidth, widest), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
