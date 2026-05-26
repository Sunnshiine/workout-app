import SwiftData
import SwiftUI

struct ExerciseCard: View {
    let exercise: Exercise
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.baseName)
                .font(.headline)

            if let note = exercise.coachNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(exercise.sets.sorted(by: { $0.index < $1.index }), id: \.persistentModelID) { set in
                    VStack(alignment: .leading, spacing: 8) {
                        SetChip(reps: set.prescribedReps, load: set.prescribedLoad)
                        if set.state == .logged, let log = set.setLog {
                            Text(log.formatted)
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        } else if set.state == .skipped {
                            Text("skip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SetLogEditor(
                            set: set,
                            onLog: { onLog(set, $0) },
                            onSkip: { onSkip(set) },
                            onDelete: { onDelete(set) }
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for row in rows {
            height += row.height
        }
        height += CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var currentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
                currentWidth = 0
            }
            rows[rows.count - 1].items.append(RowItem(index: index, size: size))
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
