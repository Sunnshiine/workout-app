import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void
    private let disablesBloom: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation: MoveOnCelebrationPresentation
    @State private var bloomPulseExpanded = false
    @State private var bloomPulseVisible = false

    private static let perfectImpactDelay: Duration = .milliseconds(120)
    private static let lensWidth: CGFloat = 210
    private static let lensHeight: CGFloat = 74
    private static let outerBloomWidth: CGFloat = 286
    private static let outerBloomHeight: CGFloat = 106
    private static let middleBloomWidth: CGFloat = 254
    private static let middleBloomHeight: CGFloat = 92
    private static let innerBloomWidth: CGFloat = 222
    private static let innerBloomHeight: CGFloat = 82
    private static let bloomStartScale = 0.74
    private static let outerBloomEndScale = 1.16
    private static let middleBloomEndScale = 1.12
    private static let innerBloomEndScale = 1.06
    private static let bloomPulseLineWidth: CGFloat = 2.2
    private static let bloomHighlightLineWidth: CGFloat = 1.1
    private static let bloomHighlightOpacity = 0.38
    private static let bloomSettleDuration = 0.28
    private static let disableBloomArgument = "-UITEST_DISABLE_CELEBRATION_BLOOM"
    private static let ink = Color(red: 0.08, green: 0.22, blue: 0.14)

    init(
        session: Session,
        disablesBloom: Bool = Self.disablesBloomForUITests,
        quoteText: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _presentation = State(initialValue: MoveOnCelebrationPresentation(session: session, quoteText: quoteText))
        self.disablesBloom = disablesBloom
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
        presentation.visualTreatment(reduceMotion: reduceMotion || disablesBloom)
    }

    private static var disablesBloomForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains(disableBloomArgument)
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
        guard let motion = presentation.bloomMotion(reduceMotion: treatment == .reducedMotionLens) else {
            bloomPulseExpanded = false
            bloomPulseVisible = false
            return
        }

        bloomPulseExpanded = false
        bloomPulseVisible = true
        await Task.yield()

        withAnimation(.easeOut(duration: motion.pulseDuration).repeatCount(motion.repeatCount, autoreverses: false)) {
            bloomPulseExpanded = true
        }

        do {
            try await Task.sleep(for: Self.duration(seconds: motion.loopDuration))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: Self.bloomSettleDuration)) {
            bloomPulseVisible = false
        }
    }

    private static func duration(seconds: TimeInterval) -> Duration {
        .nanoseconds(Int64((seconds * 1_000_000_000).rounded()))
    }

    private var contextText: some View {
        Text(presentation.contextText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(supportingTextColor)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    private var logoLens: some View {
        WorkoutGlassContainer(spacing: 0) {
            ZStack {
                if visualTreatment == .animatedBloom {
                    animatedBloom
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
                RoundedRectangle(cornerRadius: Theme.lensCornerRadius, style: .continuous)
                    .fill(palette.activeCardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.lensCornerRadius, style: .continuous)
                    .stroke(lensStrokeColor, lineWidth: lensStrokeWidth)
            }
            .workoutGlass(.lens)
            .accessibilityIdentifier("move-on-celebration-logo")
    }

    private var animatedBloom: some View {
        ZStack {
            bloomPulse(
                width: Self.outerBloomWidth,
                height: Self.outerBloomHeight,
                endScale: Self.outerBloomEndScale,
                strokeOpacity: 0.36,
                blurRadius: 5
            )
            bloomPulse(
                width: Self.middleBloomWidth,
                height: Self.middleBloomHeight,
                endScale: Self.middleBloomEndScale,
                strokeOpacity: 0.50,
                blurRadius: 2
            )
            bloomPulse(
                width: Self.innerBloomWidth,
                height: Self.innerBloomHeight,
                endScale: Self.innerBloomEndScale,
                strokeOpacity: 0.68,
                blurRadius: 0.6
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bloomPulse(
        width: CGFloat,
        height: CGFloat,
        endScale: CGFloat,
        strokeOpacity: Double,
        blurRadius: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .stroke(palette.accent.opacity(strokeOpacity), lineWidth: Self.bloomPulseLineWidth)
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .stroke(Color.white.opacity(Self.bloomHighlightOpacity), lineWidth: Self.bloomHighlightLineWidth)
                    .frame(width: width, height: height)
            }
            .shadow(color: palette.accent.opacity(strokeOpacity * 0.65), radius: blurRadius + 4)
            .blur(radius: blurRadius)
            .scaleEffect(bloomPulseExpanded ? endScale : Self.bloomStartScale)
            .opacity(bloomPulseVisible ? (bloomPulseExpanded ? 0 : 0.9) : 0)
            .accessibilityHidden(true)
    }

    private var lensStrokeColor: Color {
        switch visualTreatment {
        case .animatedBloom:
            palette.accent.opacity(0.78)
        case .reducedMotionLens:
            palette.accent.opacity(0.78)
        }
    }

    private var lensStrokeWidth: CGFloat {
        switch visualTreatment {
        case .animatedBloom:
            1.25
        case .reducedMotionLens:
            1.25
        }
    }

    private var quoteText: some View {
        Text(presentation.quoteText)
            .font(.title2.weight(.heavy))
            .foregroundStyle(palette.accent)
            .multilineTextAlignment(.center)
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
