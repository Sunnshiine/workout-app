import SwiftData
import SwiftUI

struct ActiveSetCard: View {
    private struct PillsIdentity: Hashable {
        let set: PersistentIdentifier
        let mode: SetCardMode
    }

    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var mode: SetCardSlot.Mode = .logging
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    @Environment(LastPerformedLookupStore.self) private var history
    @Environment(\.themePalette) private var palette
    @State private var inputDismissalRequestID = 0

    private static let headTargetSize: CGFloat = 44
    private static let headTargetOverhang: CGFloat = 12

    private var setCardMode: SetCardMode {
        switch mode {
        case .logging: .logging
        case .reviewingLogged: .reviewingLogged
        }
    }

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: setCardMode, set: set)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SmartValuePills(
                set: set,
                mode: setCardMode,
                suggestion: LoadSuggestionEngine.suggest(for: set, history: history.snapshot),
                onLog: onLog,
                onSkip: onSkip,
                inputDismissalRequestID: inputDismissalRequestID
            )
            .id(PillsIdentity(set: set.persistentModelID, mode: setCardMode))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardContentPadding)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.soft))
        .themeElevation(palette.surfaceShadow, in: RoundedRectangle(cornerRadius: Theme.Radius.soft))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-set-card")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Set \(setOrdinal)")
                .font(Theme.font(.setNumber))
                .foregroundColor(palette.textPrimary)
                + Text(" of \(setCount)")
                .font(Theme.font(.setOf))
                .foregroundColor(palette.textSecondary)

            Spacer(minLength: 0)
        }
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: dismissInputIfLogging)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) { headTrailingSlot }
    }

    @ViewBuilder
    private var headTrailingSlot: some View {
        if mode == .reviewingLogged(showsSavedConfirmation: true) {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(Theme.font(.setOf))
                .foregroundStyle(palette.action)
        } else if presentation.showsClearMenu {
            Menu {
                Button("Clear", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .imageScale(.large)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: Self.headTargetSize, height: Self.headTargetSize)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("clear-logged-set-menu")
            .padding(.trailing, -Self.headTargetOverhang)
        }
    }

    private func dismissInputIfLogging() {
        if case .logging = mode {
            inputDismissalRequestID += 1
        }
    }
}
