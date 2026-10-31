import SwiftUI

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var presentation: MoveOnCelebrationPresentation
    @AccessibilityFocusState private var isTitleFocused: Bool

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

            // At an accessibility text size the composition outgrows the screen, so it scrolls and
            // Move On stays pinned under it, in reach without a scroll.
            ViewThatFits(in: .vertical) {
                column(endingInContinue: true)
                VStack(spacing: 0) {
                    ScrollView { column(endingInContinue: false) }
                    continueButton
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityIdentifier("move-on-celebration")
            // The stage stays in the tree under this overlay, so the trait keeps VoiceOver off it.
            .accessibilityAddTraits(.isModal)
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .task {
            HapticPlayer.shared.play(.moveOn)
            isTitleFocused = true
        }
    }

    private func column(endingInContinue: Bool) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)

            Spacer(minLength: 12)

            Text(presentation.titleText)
                .themeFont(.ceremonyTitle)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("move-on-celebration-title")

            CeremonyBranch()
                .padding(.top, 4)

            Text(presentation.quoteText)
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 18)
                .accessibilityIdentifier("move-on-celebration-coach-line")

            statsRow
                .padding(.top, 28)

            Spacer(minLength: 12)

            if endingInContinue {
                continueButton
            }
        }
    }

    // Side by side, the header and the stats truncate at an accessibility text size, so they stack.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                contextText
                Spacer(minLength: 12)
                actionText
            }
            VStack(alignment: .leading, spacing: 4) {
                contextText
                actionText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contextText: some View {
        Text(presentation.contextText)
            .themeFont(.runline)
            .foregroundStyle(palette.textPrimary)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    private var actionText: some View {
        Text(presentation.actionText)
            .themeFont(.runlineSecondary)
            .foregroundStyle(palette.textSecondary)
            .accessibilityIdentifier("move-on-celebration-action")
    }

    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { stats }
            VStack(spacing: 10) { stats }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: 380)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.soft))
        .themeElevation(palette.surfaceShadow, in: .rect(cornerRadius: Theme.Radius.soft))
    }

    private var stats: some View {
        ForEach(presentation.stats, id: \.label) { stat in
            MoveOnCelebrationStatView(stat: stat, palette: palette)
        }
    }

    private var continueButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "sunrise")
                .themeFont(.logCapsule)
                .foregroundStyle(palette.actionText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(palette.action, in: .capsule)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(presentation.continueText)
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
                .themeFont(.statsValue)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-value")

            Text(stat.label)
                .themeFont(.statsKey)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
    }
}
