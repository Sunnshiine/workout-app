import SwiftUI

struct ActiveSetCard: View {
    /// How the card participates in the Session: logging the active pending
    /// Set, or reviewing an already-logged one with a collapse affordance.
    enum Mode {
        case logging
        case reviewingLogged(showsSavedConfirmation: Bool, onCollapse: () -> Void)

        var setCardMode: SetCardMode {
            switch self {
            case .logging: .logging
            case .reviewingLogged: .reviewingLogged
            }
        }
    }

    let exercise: Exercise
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var mode: Mode = .logging
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    var showsLoggedCheckmark = false
    var identityLabel: String?
    @Environment(\.themePalette) private var palette
    @State private var inputDismissalRequestID = 0

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: mode.setCardMode, set: set)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if case .logging = mode {
                HStack(alignment: .center, spacing: 8) {
                    if let identityLabel {
                        SupersetIdentityBadge(label: identityLabel, isActive: true)
                    }

                    Text(exercise.name)
                        .font(.headline.weight(.bold))

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
                .onTapGesture(perform: requestInputDismissal)
            }

            if let referenceText = presentation.referenceText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original Unstructured Set Log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(referenceText)
                        .font(.callout.weight(.semibold))
                }
            }

            SmartValuePills(
                set: set,
                mode: mode.setCardMode,
                previousSetWeight: previousSetWeight,
                trainingMax: trainingMax,
                onLog: onLog,
                onSkip: onSkip,
                onDelete: onDelete,
                showsLoggedCheckmarkInitially: showsLoggedCheckmark,
                inputDismissalRequestID: inputDismissalRequestID
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

    @ViewBuilder
    private var header: some View {
        switch mode {
        case .logging:
            HStack(alignment: .firstTextBaseline) {
                Text(presentation.statusText)
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
            .onTapGesture(perform: requestInputDismissal)
        case .reviewingLogged(let showsSavedConfirmation, let onCollapse):
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .textCase(.uppercase)

                    Text("Set \(setOrdinal) of \(setCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if showsSavedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }

                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.callout.weight(.semibold))
                        .accessibilityLabel("Collapse logged set")
                }
                .buttonStyle(.workoutGlass)
            }
        }
    }

    private func requestInputDismissal() {
        inputDismissalRequestID += 1
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
