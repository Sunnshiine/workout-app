import SwiftUI

struct OpenExercisesSection: View {
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open Exercises")
                .font(Theme.font(.sheetTitle))

            ForEach(exercises, id: \.persistentModelID) { exercise in
                Button {
                    onSelect(exercise)
                } label: {
                    OpenExerciseCard(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

private struct OpenExerciseCard: View {
    let exercise: Exercise
    @Environment(\.themePalette) private var palette

    var body: some View {
        let row = OpenExerciseRowPresentation(exercise: exercise)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(.primary)
                Text(row.pendingSetLabel)
                    .font(Theme.font(.historyChip))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(row.sourceLabel)
                    .font(Theme.font(.historyChip))
                Image(systemName: "chevron.right")
                    .font(Theme.font(.historyChip))
            }
            .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.pillFill, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(palette.pillStroke, lineWidth: 1)
        }
    }
}
