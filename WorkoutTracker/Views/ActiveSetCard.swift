import SwiftUI

struct ActiveSetCard: View {
    let exercise: Exercise
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .textCase(.uppercase)

                Spacer()

                Text("Set \(setOrdinal) of \(setCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: .capsule)
            }

            Text(exercise.name)
                .font(.headline.weight(.bold))

            HStack(spacing: 8) {
                SetChip(reps: set.prescribedReps, load: set.prescribedLoad)
            }

            SetLogEditor(
                set: set,
                onLog: onLog,
                onSkip: onSkip,
                onDelete: onDelete
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.white.opacity(0.08), in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }
}
