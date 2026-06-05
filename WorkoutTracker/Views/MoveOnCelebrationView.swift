import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var presentation: MoveOnCelebrationPresentation

    private static let perfectImpactDelay: Duration = .milliseconds(120)
    private static let markSize: CGFloat = 68
    private static let contentMaxWidth: CGFloat = 390

    init(
        session: Session,
        disablesBloom: Bool = false,
        quoteText: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _ = disablesBloom
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
                            .padding(.bottom, 42)

                        message

                        Spacer(minLength: 48)

                        statsRow
                            .padding(.bottom, 24)

                        Text(presentation.tapHintText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(supportingTextColor)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("move-on-celebration-hint")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .padding(.bottom, 32)
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
        .task(id: presentation.hapticStyle) {
            await playHaptics(for: presentation.hapticStyle)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(presentation.markText)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(markTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: Self.markSize, height: Self.markSize)
                .background(palette.activeCardFill, in: Circle())
                .overlay {
                    Circle()
                        .stroke(palette.activeCardStroke.opacity(0.62), lineWidth: 1)
                }
                .accessibilityIdentifier("move-on-celebration-logo")

            Spacer(minLength: 12)

            Text(presentation.contextText)
                .font(.caption.weight(.bold))
                .foregroundStyle(supportingTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("move-on-celebration-context")
        }
        .frame(maxWidth: Self.contentMaxWidth)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.actionText)
                .font(.callout.weight(.bold))
                .foregroundStyle(palette.accent)

            Text(presentation.quoteText)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(primaryTextColor)
                .lineLimit(4)
                .minimumScaleFactor(0.74)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("move-on-celebration-quote")

            Text(presentation.savedSetsText)
                .font(.body.weight(.semibold))
                .foregroundStyle(supportingTextColor)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            ForEach(presentation.stats, id: \.label) { stat in
                MoveOnCelebrationStatView(
                    stat: stat,
                    primaryTextColor: primaryTextColor,
                    supportingTextColor: supportingTextColor
                )
            }
        }
        .padding(10)
        .frame(maxWidth: Self.contentMaxWidth)
        .background(palette.pillFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(palette.pillStroke.opacity(0.7), lineWidth: 1)
        }
    }

    private var primaryTextColor: Color {
        palette.valueText
    }

    private var supportingTextColor: Color {
        palette.valueText.opacity(0.68)
    }

    private var markTextColor: Color {
        palette.preferredColorScheme == .dark ? palette.accent : palette.valueText
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
                .font(.caption.weight(.bold))
                .foregroundStyle(supportingTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
