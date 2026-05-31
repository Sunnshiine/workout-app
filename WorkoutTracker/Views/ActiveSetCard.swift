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
    var identityLabel: String?
    @Environment(\.themePalette) private var palette
    @State private var dismissFieldUIRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .textCase(.uppercase)

                Spacer()

                Text("Set \(setOrdinal) of \(setCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.badgeFill, in: .capsule)
            }
            .contentShape(.rect)
            .onTapGesture(perform: dismissFieldUI)

            HStack(alignment: .center, spacing: 8) {
                if let identityLabel {
                    SupersetIdentityBadge(label: identityLabel, isActive: true)
                }

                Text(exercise.name)
                    .font(.headline.weight(.bold))

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .onTapGesture(perform: dismissFieldUI)

            SmartValuePills(
                set: set,
                previousSetWeight: previousSetWeight,
                trainingMax: trainingMax,
                onLog: onLog,
                onSkip: onSkip,
                onDelete: onDelete,
                dismissFieldUIRequest: dismissFieldUIRequest,
                showsLoggedCheckmarkInitially: showsLoggedCheckmark
            )
            .id(set.persistentModelID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(palette.activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(palette.activeCardStroke.opacity(0.8), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-set-card")
    }

    private func dismissFieldUI() {
        dismissFieldUIRequest += 1
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
