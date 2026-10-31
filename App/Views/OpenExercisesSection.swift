import SwiftUI

struct OpenExercisesSection: View {
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open Exercises")
                .themeFont(.heading)

            ForEach(exercises, id: \.persistentModelID) { exercise in
                Button {
                    onSelect(exercise)
                } label: {
                    OpenExerciseRow(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

private struct OpenExerciseRow: View {
    let exercise: Exercise
    @Environment(\.themePalette) private var palette

    var body: some View {
        let row = OpenExerciseRowPresentation(exercise: exercise)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .themeFont(.queuePill)
                    .foregroundStyle(.primary)
                Text(row.pendingSetLabel)
                    .themeFont(.historyChip)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(row.sessionAddressLabel)
                    .themeFont(.historyChip)
                Image(systemName: "chevron.right")
                    .themeFont(.historyChip)
            }
            .foregroundStyle(palette.actionInk)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
