import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette
    @State private var presentation: MoveOnCelebrationPresentation

    private static let perfectImpactDelay: Duration = .milliseconds(120)
    private static let orbitRefreshInterval = 1.0 / 30.0

    init(
        session: Session,
        requestedAt: Date? = nil,
        quoteText: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _presentation = State(
            initialValue: MoveOnCelebrationPresentation(session: session, requestedAt: requestedAt, quoteText: quoteText)
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            palette.paperBackground
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
                        .padding(.bottom, 42)

                        timingCenter
                            .padding(.bottom, 34)

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
            .font(Theme.glyphFont(size: 18, weight: .black, design: .rounded))
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
            .font(Theme.glyphFont(size: 34, weight: .black))
            .foregroundStyle(primaryTextColor)
            .multilineTextAlignment(.leading)
            .lineLimit(6)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 340, alignment: .bottomLeading)
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

    @ViewBuilder
    private var timingCenter: some View {
        if case .available(let elapsedText, let timeRangeText) = presentation.timing {
            VStack(spacing: 12) {
                timingNucleus(elapsedText: elapsedText)

                Text(timeRangeText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(supportingTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityLabel("Time range")
                    .accessibilityValue(timeRangeText.replacingOccurrences(of: "→", with: "to"))
                    .accessibilityIdentifier("move-on-celebration-time-range")
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func timingNucleus(elapsedText: String) -> some View {
        if reduceMotion {
            timingNucleusContent(elapsedText: elapsedText, phase: 0)
        } else {
            TimelineView(.animation(minimumInterval: Self.orbitRefreshInterval)) { context in
                timingNucleusContent(
                    elapsedText: elapsedText,
                    phase: context.date.timeIntervalSinceReferenceDate
                )
            }
        }
    }

    private func timingNucleusContent(elapsedText: String, phase: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(palette.activeCardFill.opacity(0.78))
                .frame(width: 144, height: 144)
                .scaleEffect(nucleusScale(for: phase))
                .accessibilityHidden(true)

            Circle()
                .stroke(palette.accent.opacity(0.34), lineWidth: 1)
                .frame(width: 144, height: 144)
                .scaleEffect(outerRingScale(for: phase))
                .accessibilityHidden(true)

            Circle()
                .stroke(palette.pillStroke.opacity(0.46), lineWidth: 1)
                .frame(width: 106, height: 106)
                .accessibilityHidden(true)

            orbitLayer(phase: phase)
                .accessibilityHidden(true)
                .accessibilityIdentifier("move-on-celebration-orbit")

            Text(elapsedText)
                .font(Theme.glyphFont(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(primaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 94)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(elapsedText)
                .accessibilityIdentifier("move-on-celebration-elapsed-nucleus")
        }
        .frame(width: 154, height: 154)
    }

    private func orbitLayer(phase: TimeInterval) -> some View {
        ZStack {
            orbitDot(phase: phase, offset: 0, radius: 70, size: 7, opacity: 0.78)
            orbitDot(phase: phase, offset: 2.18, radius: 57, size: 5, opacity: 0.58)
            orbitDot(phase: phase, offset: 4.36, radius: 66, size: 4, opacity: 0.48)
        }
    }

    private func orbitDot(
        phase: TimeInterval,
        offset: Double,
        radius: CGFloat,
        size: CGFloat,
        opacity: Double
    ) -> some View {
        let angle = phase * 0.42 + offset
        let x = CGFloat(cos(angle)) * radius
        let y = CGFloat(sin(angle)) * radius * 0.58

        return Circle()
            .fill(palette.accent.opacity(opacity))
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }

    private func nucleusScale(for phase: TimeInterval) -> CGFloat {
        reduceMotion ? 1 : 1 + (CGFloat(sin(phase * 1.1)) * 0.018)
    }

    private func outerRingScale(for phase: TimeInterval) -> CGFloat {
        reduceMotion ? 1 : 1 + (CGFloat(sin(phase * 0.72)) * 0.028)
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
