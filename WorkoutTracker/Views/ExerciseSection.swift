import SwiftUI

struct ExerciseSection: View {
    let exercise: Exercise
    let activeSetID: ActiveSetID?
    let onFocus: (ExerciseSet) -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void

    private var sortedSets: [ExerciseSet] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exercise.name)
                .font(.headline)

            if let note = exercise.coachNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sortedSets, id: \.persistentModelID) { set in
                    if ActiveSetFocusManager.id(for: set) == activeSetID {
                        ActiveSetCard(
                            exercise: exercise,
                            set: set,
                            setOrdinal: setOrdinal(for: set),
                            setCount: sortedSets.count,
                            onLog: { onLog(set, $0) },
                            onSkip: { onSkip(set) },
                            onDelete: { onDelete(set) }
                        )
                    } else {
                        SetRow(set: set) {
                            onFocus(set)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }

    private func setOrdinal(for set: ExerciseSet) -> Int {
        (sortedSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
    }
}
