import SwiftData
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

    private struct PillsIdentity: Hashable {
        let set: PersistentIdentifier
        let mode: SetCardMode
    }

    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var mode: Mode = .logging
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    @Environment(LastPerformedLookupStore.self) private var history
    @Environment(\.themePalette) private var palette
    @State private var inputDismissalRequestID = 0

    private static let headTargetSize: CGFloat = 44
    private static let headTargetOverhang: CGFloat = 12

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: mode.setCardMode, set: set)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SmartValuePills(
                set: set,
                mode: mode.setCardMode,
                suggestion: LoadSuggestionEngine.suggest(for: set, history: history.snapshot),
                onLog: onLog,
                onSkip: onSkip,
                inputDismissalRequestID: inputDismissalRequestID
            )
            .id(PillsIdentity(set: set.persistentModelID, mode: mode.setCardMode))
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

    private var headTrailingSlot: some View {
        HStack(spacing: 0) {
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
                        .frame(width: Self.headTargetSize, height: Self.headTargetSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse logged set")
            }

            if presentation.showsClearMenu {
                Menu {
                    Button("Clear", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: Self.headTargetSize, height: Self.headTargetSize)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier("clear-logged-set-menu")
            }
        }
        .padding(.trailing, -Self.headTargetOverhang)
    }

    private func dismissInputIfLogging() {
        if case .logging = mode {
            inputDismissalRequestID += 1
        }
    }
}
