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

    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var mode: Mode = .logging
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    var showsLoggedCheckmark = false
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
                suggestion: LoadSuggestionEngine.suggest(for: set),
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
}
