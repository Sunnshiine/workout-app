import SwiftUI

struct ActiveSetCard: View {
    let exercise: Exercise
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    var showsLoggedCheckmark = false

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

            SmartValuePills(
                set: set,
                previousSetWeight: previousSetWeight,
                trainingMax: trainingMax,
                onLog: onLog,
                onSkip: onSkip,
                onDelete: onDelete,
                showsLoggedCheckmarkInitially: showsLoggedCheckmark
            )
            .id(set.persistentModelID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.activeCardStroke.opacity(0.8), lineWidth: 1)
        )
    }

    private var previousSetWeight: Double? {
        exercise.sets
            .filter { $0.index < set.index }
            .sorted { $0.index > $1.index }
            .compactMap { previousSet -> Double? in
                switch previousSet.setLog?.weight {
                case .pounds(let pounds):
                    return pounds
                case .bodyweight, nil:
                    return nil
                }
            }
            .first
    }

    private var trainingMax: Double? {
        guard let block = exercise.session?.week?.block else { return nil }
        let baseName = exercise.baseName.lowercased()
        if baseName.contains("squat") { return block.squatTM }
        if baseName.contains("bench") { return block.benchTM }
        if baseName.contains("deadlift") { return block.deadliftTM }
        return nil
    }
}
