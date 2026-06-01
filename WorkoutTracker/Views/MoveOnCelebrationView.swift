import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @State private var presentation: MoveOnCelebrationPresentation

    private static let perfectImpactDelay: Duration = .milliseconds(120)
    private static let lensWidth: CGFloat = 210
    private static let lensHeight: CGFloat = 74
    private static let lensCornerRadius: CGFloat = 28
    private static let ink = Color(red: 0.08, green: 0.22, blue: 0.14)

    init(session: Session, onDismiss: @escaping () -> Void) {
        _presentation = State(initialValue: MoveOnCelebrationPresentation(session: session))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            palette.gradient
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        VStack(spacing: 22) {
                            contextText
                            logoLens
                            quoteText
                            statsRow
                        }
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: 24)

                        Text("Tap anywhere to continue")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(supportingTextColor)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("move-on-celebration-hint")
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
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

    private var palette: Theme.Palette {
        Theme.palette(for: .sageLight)
    }

    private var primaryTextColor: Color {
        Self.ink
    }

    private var supportingTextColor: Color {
        Self.ink.opacity(0.68)
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

    private var contextText: some View {
        Text(presentation.contextText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(supportingTextColor)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    private var logoLens: some View {
        Text("TFN")
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundStyle(primaryTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: Self.lensWidth, height: Self.lensHeight)
            .background {
                RoundedRectangle(cornerRadius: Self.lensCornerRadius, style: .continuous)
                    .fill(palette.activeCardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.lensCornerRadius, style: .continuous)
                    .stroke(palette.activeCardStroke.opacity(0.52), lineWidth: 1)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: Self.lensCornerRadius))
            .accessibilityIdentifier("move-on-celebration-logo")
    }

    private var quoteText: some View {
        Text(presentation.quoteText)
            .font(.title2.weight(.heavy))
            .foregroundStyle(palette.accent)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: 340, minHeight: 92)
            .accessibilityIdentifier("move-on-celebration-quote")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
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
