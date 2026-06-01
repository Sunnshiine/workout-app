import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation: MoveOnCelebrationPresentation
    @State private var bloomHasAppeared = false

    private static let perfectImpactDelay: Duration = .milliseconds(120)
    private static let lensWidth: CGFloat = 210
    private static let lensHeight: CGFloat = 74
    private static let lensCornerRadius: CGFloat = 28
    private static let bloomWidth: CGFloat = 258
    private static let bloomHeight: CGFloat = 104
    private static let bloomCornerRadius: CGFloat = 36
    private static let bloomDuration = 0.36
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
        .task(id: visualTreatment) {
            await prepareBloom(for: visualTreatment)
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

    private var visualTreatment: MoveOnCelebrationVisualTreatment {
        presentation.visualTreatment(reduceMotion: reduceMotion)
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

    @MainActor
    private func prepareBloom(for treatment: MoveOnCelebrationVisualTreatment) async {
        guard treatment == .animatedPerfectBloom else {
            bloomHasAppeared = false
            return
        }
        guard !bloomHasAppeared else { return }

        withAnimation(.easeOut(duration: Self.bloomDuration)) {
            bloomHasAppeared = true
        }
    }

    private var contextText: some View {
        Text(presentation.contextText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(supportingTextColor)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    private var logoLens: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                if visualTreatment == .animatedPerfectBloom {
                    perfectBloom
                }
                logoMark
            }
        }
    }

    private var logoMark: some View {
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
                    .stroke(lensStrokeColor, lineWidth: lensStrokeWidth)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: Self.lensCornerRadius))
            .accessibilityIdentifier("move-on-celebration-logo")
    }

    private var perfectBloom: some View {
        RoundedRectangle(cornerRadius: Self.bloomCornerRadius, style: .continuous)
            .fill(palette.activeCardFill.opacity(0.58))
            .frame(width: Self.bloomWidth, height: Self.bloomHeight)
            .overlay {
                RoundedRectangle(cornerRadius: Self.bloomCornerRadius, style: .continuous)
                    .stroke(palette.accent.opacity(0.44), lineWidth: 1)
            }
            .scaleEffect(bloomHasAppeared ? 1 : 0.88)
            .opacity(bloomHasAppeared ? 1 : 0)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.bloomCornerRadius))
            .accessibilityHidden(true)
    }

    private var lensStrokeColor: Color {
        switch visualTreatment {
        case .standardLens:
            palette.activeCardStroke.opacity(0.52)
        case .animatedPerfectBloom, .reducedMotionPerfectLens:
            palette.accent.opacity(0.78)
        }
    }

    private var lensStrokeWidth: CGFloat {
        switch visualTreatment {
        case .standardLens:
            1
        case .animatedPerfectBloom, .reducedMotionPerfectLens:
            1.25
        }
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
