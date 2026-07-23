import SwiftUI

/// The one soft container (DESIGN.md §5.2, pick input-block3-c): radius `soft` 30, the day double
/// `surfaceShadow` / night inset cream border, padding 16/16/14. Its head is a plain `Set N of M`;
/// the uppercase status microlabel, the carved capsule badge, and the in-card Exercise-name repeat
/// are gone (ledger §2.2–2.3). The input block itself is `SmartValuePills`.
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
    /// Retained for the Superset composition (#489); the card no longer repeats the Exercise name
    /// or its badge inside itself (ledger §2.3).
    var identityLabel: String?
    @Environment(\.themePalette) private var palette
    @State private var inputDismissalRequestID = 0

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: mode.setCardMode, set: set)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let referenceText = presentation.referenceText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original Unstructured Set Log")
                        .font(Theme.font(.fieldLabel))
                        .foregroundStyle(palette.textSecondary)
                    Text(referenceText)
                        .font(Theme.font(.runline))
                        .foregroundStyle(palette.textPrimary)
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
        .padding(Theme.cardContentPadding)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.soft))
        .themeElevation(palette.surfaceShadow, in: RoundedRectangle(cornerRadius: Theme.Radius.soft))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-set-card")
    }

    // The plain `Set N of M` head: `Set 3` in 16pt/700 tnum, ` of 5` in 14pt/500 muted. Reviewing a
    // logged Set adds the Saved confirmation and a collapse chevron on the trailing edge.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Set \(setOrdinal)")
                .font(Theme.font(.setNumber))
                .foregroundColor(palette.textPrimary)
                + Text(" of \(setCount)")
                .font(Theme.font(.setOf))
                .foregroundColor(palette.textSecondary)

            Spacer(minLength: 0)

            if case .reviewingLogged(let showsSavedConfirmation, let onCollapse) = mode {
                if showsSavedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(Theme.font(.setOf))
                        .foregroundStyle(palette.action)
                }

                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .imageScale(.medium)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityLabel("Collapse logged set")
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: dismissInputIfLogging)
    }

    private func dismissInputIfLogging() {
        if case .logging = mode {
            inputDismissalRequestID += 1
        }
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
