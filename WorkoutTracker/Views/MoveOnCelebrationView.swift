import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var presentation: MoveOnCelebrationPresentation

    private static let perfectImpactDelay: Duration = .milliseconds(120)

    init(
        session: Session,
        quoteText: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _presentation = State(initialValue: MoveOnCelebrationPresentation(session: session, quoteText: quoteText))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            palette.gradient
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                            .padding(.bottom, 44)

                        VStack(alignment: .leading, spacing: 10) {
                            actionText
                            quoteText
                            setsCopyText
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 54)

                        Spacer(minLength: 0)

                        VStack(spacing: 22) {
                            statsRow

                            Text(presentation.tapHintText)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(supportingTextColor)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("move-on-celebration-hint")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .accessibilityLabel(presentation.accessibilityLabel)
                .accessibilityValue(presentation.accessibilityValue)
                .accessibilityHint(presentation.accessibilityHint)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("move-on-celebration")
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            }
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .task(id: presentation.hapticStyle) {
            await playHaptics(for: presentation.hapticStyle)
        }
    }

    private var primaryTextColor: Color {
        palette.valueText
    }

    private var supportingTextColor: Color {
        palette.valueText.opacity(0.68)
    }

    @MainActor
    private func playHaptics(for style: MoveOnCelebrationHapticStyle) async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard style == .successWithImpact else { return }
        do {
            try await Task.sleep(for: Self.perfectImpactDelay)
        } catch {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private var header: some View {
        HStack(alignment: .center) {
            logoMark
            Spacer(minLength: 14)
            contextText
        }
    }

    private var contextText: some View {
        Text(presentation.contextText)
            .font(.caption.weight(.bold))
            .foregroundStyle(supportingTextColor)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    private var logoMark: some View {
        Text(presentation.markText)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(palette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: 68, height: 68)
            .background(palette.activeCardFill, in: Circle())
            .overlay {
                Circle()
                    .stroke(palette.accent.opacity(0.48), lineWidth: 1)
            }
            .accessibilityIdentifier("move-on-celebration-logo")
    }

    private var actionText: some View {
        Text(presentation.actionText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(palette.accent)
            .accessibilityIdentifier("move-on-celebration-action")
    }

    private var quoteText: some View {
        Text(presentation.quoteText)
            .font(.system(size: 38, weight: .black, design: .default))
            .foregroundStyle(primaryTextColor)
            .multilineTextAlignment(.leading)
            .lineLimit(4)
            .minimumScaleFactor(0.68)
            .frame(maxWidth: 340, minHeight: 96, alignment: .bottomLeading)
            .accessibilityIdentifier("move-on-celebration-quote")
    }

    private var setsCopyText: some View {
        Text(presentation.setsCopyText)
            .font(.body.weight(.semibold))
            .foregroundStyle(supportingTextColor)
            .lineSpacing(2)
            .frame(maxWidth: 310, alignment: .leading)
            .accessibilityIdentifier("move-on-celebration-sets-copy")
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ForEach(presentation.stats, id: \.label) { stat in
                MoveOnCelebrationStatView(
                    stat: stat,
                    primaryTextColor: primaryTextColor,
                    supportingTextColor: supportingTextColor
                )
            }
        }
        .padding(10)
        .frame(maxWidth: 380)
        .background(palette.pillFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(palette.pillStroke.opacity(0.7), lineWidth: 1)
        }
    }

}

private struct MoveOnCelebrationStatView: View {
    let stat: MoveOnCelebrationStatPresentation
    let primaryTextColor: Color
    let supportingTextColor: Color

    private var identifierKey: String {
        stat.label.lowercased()
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(.title2.weight(.black))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-value")

            Text(stat.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(supportingTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
    }
}
