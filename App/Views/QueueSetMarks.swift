import SwiftUI

/// One mark per Set, so a row shows how much of the Exercise there is before it is on stage. Marks
/// narrow together when a long Superset would overrun the row.
struct QueueSetMarks: View {
    let sets: [ExerciseSet]
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(sets, id: \.persistentModelID) { set in
                mark(for: set)
                    .frame(minWidth: 4, maxWidth: 20)
                    .frame(height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private func mark(for set: ExerciseSet) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5)
        switch set.state {
        case .logged:
            shape.fill(palette.action)
        case .skipped:
            shape.strokeBorder(palette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .pending:
            shape.strokeBorder(palette.textSecondary, lineWidth: 1)
        }
    }
}
