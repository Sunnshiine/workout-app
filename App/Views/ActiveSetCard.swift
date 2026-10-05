import SwiftUI

struct ActiveSetCard: View {
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var mode: SetCardMode = .logging
    var showsSavedConfirmation = false
    var onCollapse: () -> Void = {}
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    var showsLoggedCheckmark = false
    @Environment(LastPerformedLookupStore.self) private var history
    @Environment(\.themePalette) private var palette
    @State private var inputDismissalRequestID = 0

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: mode, set: set)
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
                mode: mode,
                suggestion: LoadSuggestionEngine.suggest(for: set, history: history.snapshot),
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

            if mode == .reviewingLogged {
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
        if mode == .logging {
            inputDismissalRequestID += 1
        }
    }
}
