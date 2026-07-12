import SwiftUI

/// The Exercise History sheet (revised `DESIGN.md` §Exercise History Sheet): a quiet `.medium`
/// detent opened from the Last Performed line, showing the last ~5 entries for the viewed
/// Exercise's Movement. It stays entirely in the Last Performed reference vocabulary — muted text,
/// hairline rules, no glass, no mint — so the Warm Training Cockpit stage keeps visual priority.
struct ExerciseHistorySheet: View {
    let presentation: ExerciseHistorySheetPresentation
    /// The fill-in-progress affordance, present only while history for this Movement may still
    /// deepen (sub-issue #366). `nil` once the fill has reached coverage or exhausted the tabs.
    var fillProgress: HistoryFillProgressPresentation?

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
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { _, block in
                        blockSection(block)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.title)
                .font(.headline)
            Text(presentation.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// A visible, playful fill affordance in the product's warm voice: a warm line, a muted
    /// determinate bar, and an honest per-tab detail — never mint, never a dead spinner (revised
    /// `DESIGN.md`). Existing entries stay readable beneath it; it never blocks the list.
    private func fillAffordance(_ progress: HistoryFillProgressPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ProgressView(value: progress.fraction)
                .tint(.secondary)
            Text(progress.detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-fill-progress")
    }

    private func blockSection(_ block: ExerciseHistorySheetPresentation.Block) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(block.header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            // Hairline rule under the Block header.
            Divider()
            ForEach(Array(block.rows.enumerated()), id: \.offset) { _, row in
                ExerciseHistoryRow(row: row)
            }
        }
    }
}

/// One entry: a `Wn Dn` gutter with the entry's Cadence beneath it, then the Sets on a single line
/// that never wraps — long Set lists shrink to fit (`lineLimit(1)` + `minimumScaleFactor`) rather
/// than wrapping (the History Row Never Wraps Rule).
private struct ExerciseHistoryRow: View {
    let row: ExerciseHistorySheetPresentation.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.gutter)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if let cadence = row.cadence {
                    Text(cadence)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 46, alignment: .leading)

            setsLine
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var setsLine: Text {
        var pieces: [Text] = []
        for (index, segment) in row.segments.enumerated() {
            if index > 0 { pieces.append(separator) }
            pieces.append(text(for: segment))
        }
        if let asName = row.asName {
            pieces.append(Text("  as “\(asName)”").italic().foregroundStyle(.tertiary))
        }
        if row.asEntered {
            pieces.append(Text("  as entered").italic().foregroundStyle(.tertiary))
        }
        return pieces.reduce(Text(""), +)
    }

    private var separator: Text {
        Text(" · ").foregroundStyle(.tertiary)
    }

    private func text(for segment: ExerciseHistorySheetPresentation.SetSegment) -> Text {
        switch segment {
        case .log(let load, let rpe):
            let base = Text(load)
            guard let rpe else { return base }
            // Muted RPE trailing the load.
            return base + Text(" @\(rpe)").foregroundStyle(.tertiary)
        case .skip:
            return Text("skip").italic().foregroundStyle(.tertiary)
        case .raw(let value):
            return Text(value).italic()
        }
    }
}
