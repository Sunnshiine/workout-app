import SwiftUI
import UIKit

struct MoveOnCelebrationView: View {
    let presentation: MoveOnCelebrationPresentation
    let onDismiss: () -> Void

    @State private var quoteIndex = 0
    @State private var ripplesExpanded = false

    private static let quoteRotationInterval: Duration = .seconds(2.4)
    private static let quoteAnimation = Animation.easeInOut(duration: 0.28)
    private static let perfectImpactDelay: Duration = .milliseconds(120)
    private static let stampSize: CGFloat = 112
    private static let rippleDiameter: CGFloat = 188

    init(session: Session, onDismiss: @escaping () -> Void) {
        self.presentation = MoveOnCelebrationPresentation(session: session)
        self.onDismiss = onDismiss
    }

    private var quoteText: String {
        guard !presentation.quotes.isEmpty else { return "" }
        return presentation.quotes[quoteIndex % presentation.quotes.count]
    }

    var body: some View {
        ZStack {
            Theme.gradient
                .ignoresSafeArea()
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 26)

                        VStack(spacing: 20) {
                            stamp
                            copyStack
                            statsRow
                        }
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: 20)

                        Text("Tap anywhere to continue")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .opacity(0.72)
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
                .accessibilityHint("Advances to the next session")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("move-on-celebration")
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            }
        }
        .animation(Self.quoteAnimation, value: quoteText)
        .onAppear {
            ripplesExpanded = true
        }
        .task(id: presentation.hapticStyle) {
            await playHaptics(for: presentation.hapticStyle)
        }
        .task {
            guard presentation.quotes.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.quoteRotationInterval)
                guard !Task.isCancelled else { return }
                withAnimation(Self.quoteAnimation) {
                    quoteIndex = (quoteIndex + 1) % presentation.quotes.count
                }
            }
        }
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

    private var copyStack: some View {
        VStack(spacing: 10) {
            Text(quoteText)
                .id(quoteText)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .accessibilityIdentifier("move-on-celebration-quote")

            Text(presentation.weekText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(presentation.titleText)
                .font(.largeTitle.weight(.black))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .accessibilityIdentifier("move-on-celebration-title")

            Text(presentation.sublineText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("move-on-celebration-subline")
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ForEach(presentation.stats, id: \.label) { stat in
                MoveOnCelebrationStatView(stat: stat)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: 380)
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(Theme.pillStroke.opacity(0.7), lineWidth: 1)
        }
    }

    private var stamp: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Theme.accent.opacity(ripplesExpanded ? 0 : 0.34), lineWidth: 2)
                    .frame(width: Self.stampSize, height: Self.stampSize)
                    .scaleEffect(ripplesExpanded ? 1.34 + CGFloat(index) * 0.22 : 0.72)
                    .animation(
                        .easeOut(duration: 1.15)
                            .delay(Double(index) * 0.18)
                            .repeatForever(autoreverses: false),
                        value: ripplesExpanded
                    )
            }

            Circle()
                .fill(Theme.accent)
                .frame(width: Self.stampSize, height: Self.stampSize)
                .shadow(color: Theme.accent.opacity(0.55), radius: 28, y: 12)
                .overlay {
                    Circle()
                        .stroke(Theme.accentDarkText.opacity(0.34), lineWidth: 5)
                        .padding(8)
                }
                .overlay {
                    Circle()
                        .stroke(
                            Theme.accentDarkText.opacity(0.48),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6])
                        )
                        .padding(20)
                }

            Image(systemName: "checkmark")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Theme.accentDarkText)
                .offset(y: 2)
        }
        .frame(width: Self.rippleDiameter, height: Self.rippleDiameter)
        .rotationEffect(.degrees(-7))
        .accessibilityHidden(true)
    }
}

private struct MoveOnCelebrationStatView: View {
    let stat: MoveOnCelebrationStatPresentation

    private var identifierKey: String {
        stat.label.lowercased()
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(.title2.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-value")

            Text(stat.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
    }
}
