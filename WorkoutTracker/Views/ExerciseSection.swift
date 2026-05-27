import SwiftUI

struct ExerciseSection: View {
    let exercise: Exercise
    let lastPerformedIndex: LastPerformedIndex
    let activeSetID: ActiveSetID?
    let isCollapsed: Bool
    let onFocus: (ExerciseSet) -> Void
    let onReexpand: () -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void

    private var sortedSets: [ExerciseSet] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    private var lastPerformedPresentation: LastPerformedCardPresentation? {
        LastPerformedCardPresentation(exercise: exercise, index: lastPerformedIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCollapsed {
                ExerciseSummaryRow(exercise: exercise, onTap: onReexpand)
            } else {
                Text(exercise.name)
                    .font(.headline)

                if let note = exercise.coachNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let lastPerformedPresentation {
                    LastPerformedCard(presentation: lastPerformedPresentation)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }

    private func setOrdinal(for set: ExerciseSet) -> Int {
        (sortedSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
    }
}
