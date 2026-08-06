import SwiftUI

/// The Move On ceremony (DESIGN.md §5.7, picks sunbird-moments-a/-d): the app's
/// one large celebratory moment, marking the athlete's explicit choice to Move On.
/// On living paper a Fraunces title names the finished day, a grown branch carries
/// the perched songbird at its tip (the colophon is absent — the bird replaces
/// it), the coach's line reads below, the day's stats sit on the shared soft
/// surface, and a full-width green **Continue** capsule closes it. Completion, not
/// achievement: no elapsed-time UI, no perfect-Session variant, no confetti.
struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette
    @State private var presentation: MoveOnCelebrationPresentation
    @State private var hapticPlayer = MoveOnHapticPlayer()

    init(
        session: Session,
        quoteText: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _presentation = State(
            initialValue: MoveOnCelebrationPresentation(session: session, quoteText: quoteText)
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            palette.paperBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                Spacer(minLength: 12)

                Text(presentation.titleText)
                    .font(Theme.font(.ceremonyTitle))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("move-on-celebration-title")

                CeremonyBranch()
                    .padding(.top, 4)

                Text(presentation.quoteText)
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.top, 18)
                    .accessibilityIdentifier("move-on-celebration-coach-line")

                statsRow
                    .padding(.top, 28)

                Spacer(minLength: 12)

                continueButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityIdentifier("move-on-celebration")
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .task {
            guard !reduceMotion else { return }
            hapticPlayer.play()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(presentation.contextText)
                .font(Theme.font(.runline))
                .foregroundStyle(palette.textPrimary)
                .accessibilityIdentifier("move-on-celebration-context")

            Spacer(minLength: 12)

            // The `Move On` microlabel loses its uppercase, tracked, action-green
            // register (ledger §8) — it is a quiet secondary line, not a button.
            Text(presentation.actionText)
                .font(Theme.font(.runlineSecondary))
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("move-on-celebration-action")
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ForEach(presentation.stats, id: \.label) { stat in
                MoveOnCelebrationStatView(stat: stat, palette: palette)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: 380)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.soft))
        .themeElevation(palette.surfaceShadow, in: .rect(cornerRadius: Theme.Radius.soft))
    }

    private var continueButton: some View {
        Button(action: onDismiss) {
            Text(presentation.continueText)
                .font(Theme.font(.logCapsule))
                .foregroundStyle(palette.actionText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(palette.action, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityIdentifier("move-on-celebration-continue")
    }
}

private struct MoveOnCelebrationStatView: View {
    let stat: MoveOnCelebrationStatPresentation
    let palette: Theme.Palette

    private var identifierKey: String {
        stat.label.lowercased()
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(Theme.font(.statsValue))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-value")

            Text(stat.label)
                .font(Theme.font(.statsKey))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
    }
}
