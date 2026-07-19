import SwiftUI
import UIKit

/// The Move On ceremony — the only performed growth in the app (DESIGN.md §5.7).
/// On living paper the stem grows (1.0s), pauses a beat (0.10s), and the perched
/// songbird drops to the branch tip (0.35s) — ≈1.5s total, at Brisk, all on the
/// wing ease. The Fraunces ceremony title speaks; stats render on the shared soft
/// surface. There is no perfect-Session variant: the ceremony is identical on an
/// ordinary day with Skipped Sets and on a perfect Session (Completion, Not
/// Achievement). With the bird present the colophon is absent and the composition
/// re-centers. Reduced Motion crossfades to the fully-grown end state; the one
/// swell-and-peak Move On haptic is unaffected.
struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette
    @State private var presentation: MoveOnCelebrationPresentation
    @State private var growth: CGFloat = 0
    @State private var birdLanded = false

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
            palette.paperBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        context
                            .padding(.bottom, 10)

                        ceremonyTitle
                            .padding(.bottom, 6)

                        action
                            .padding(.bottom, 30)

                        CeremonyBranch(growth: growth, birdLanded: birdLanded, reduceMotion: reduceMotion)
                            .frame(height: 150)
                            .padding(.bottom, 34)

                        statsSurface
                            .padding(.bottom, 20)

                        setsCopy

                        Spacer(minLength: 0)

                        tapHint
                            .padding(.top, 30)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 30)
                    .padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
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
        .task { await runCeremony() }
    }

    // MARK: - Composition

    private var context: some View {
        Text(presentation.contextText)
            .font(Theme.font(.cadence))
            .foregroundStyle(palette.textSecondary)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    private var ceremonyTitle: some View {
        Text(presentation.quoteText)
            .font(Theme.font(.ceremonyTitle))
            .foregroundStyle(palette.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.68)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 340)
            .accessibilityIdentifier("move-on-celebration-quote")
    }

    private var action: some View {
        Text(presentation.actionText)
            .font(Theme.font(.fieldLabel))
            .foregroundStyle(palette.action)
            .textCase(.uppercase)
            .tracking(1.4)
            .accessibilityIdentifier("move-on-celebration-action")
    }

    private var setsCopy: some View {
        Text(presentation.setsCopyText)
            .font(Theme.font(.coachNote))
            .foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            .accessibilityIdentifier("move-on-celebration-sets-copy")
    }

    private var tapHint: some View {
        Text(presentation.tapHintText)
            .font(Theme.font(.queuePill))
            .foregroundStyle(palette.textSecondary.opacity(0.85))
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("move-on-celebration-hint")
    }

    // The one soft container: the ceremony stats, no dashboard chrome.
    private var statsSurface: some View {
        HStack(spacing: 6) {
            ForEach(presentation.stats, id: \.label) { stat in
                MoveOnCelebrationStatView(stat: stat)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: 360)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.soft))
        .overlay {
            if isNight {
                RoundedRectangle(cornerRadius: Theme.Radius.soft)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
        .shadow(color: daySurfaceShadow, radius: 18, y: 10)
        .shadow(color: daySurfaceShadow.opacity(0.6), radius: 3, y: 1)
        .accessibilityElement(children: .combine)
    }

    private var isNight: Bool { palette.appearance == .night }

    private var daySurfaceShadow: Color {
        isNight ? .clear : Color.black.opacity(0.08)
    }

    // MARK: - Choreography (≈1.5s, Brisk)

    @MainActor
    private func runCeremony() async {
        // End states in Reduced Motion; the parent's opacity transition crossfades
        // the ceremony in fully grown.
        if reduceMotion {
            growth = 1
            birdLanded = true
        } else {
            withAnimation(Theme.wingAnimation(duration: Theme.Motion.ceremonyStem)) { growth = 1 }
        }

        // Swell — the first half of the one Move On haptic pattern, as the stem grows.
        playSwell()

        try? await Task.sleep(for: .seconds(Theme.Motion.ceremonyStem + Theme.Motion.ceremonyBeat))

        if !reduceMotion {
            withAnimation(Theme.wingAnimation(duration: Theme.Motion.ceremonyBird)) { birdLanded = true }
        }

        // Peak — the bird lands.
        playPeak()
    }

    private func playSwell() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }

    private func playPeak() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

private struct MoveOnCelebrationStatView: View {
    let stat: MoveOnCelebrationStatPresentation
    @Environment(\.themePalette) private var palette

    private var identifierKey: String { stat.label.lowercased() }

    var body: some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(Theme.font(.statsValue))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-value")

            Text(stat.label)
                .font(Theme.font(.statsKey))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
    }
}

/// The ceremonial stem — the stage's branch grown once, at Brisk. The stem draws
/// in left-to-right (`growth`), a few leaves ink in behind the growing tip in the
/// leaf language, and the perched songbird drops onto the tip (`birdLanded`). The
/// stem is deliberately identical every day — it carries no Set-State reading, so
/// the ceremony never curdles on an ordinary day with Skipped Sets.
private struct CeremonyBranch: View {
    let growth: CGFloat
    let birdLanded: Bool
    let reduceMotion: Bool
    @Environment(\.themePalette) private var palette

    // Fixed leaf anchors along the stem's 0→1 parameter, above/below alternating.
    private let leaves: [(t: CGFloat, above: Bool)] = [(0.32, true), (0.58, false), (0.82, true)]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tip = stemTip(in: size)

            ZStack {
                CeremonyStem()
                    .trim(from: 0, to: max(0.001, growth))
                    .stroke(palette.stem, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                ForEach(Array(leaves.enumerated()), id: \.offset) { _, leaf in
                    leafGlyph(revealed: growth >= leaf.t, above: leaf.above)
                        .position(stemPoint(at: leaf.t, in: size))
                }

                PerchedSongbird(height: 72)
                    .opacity(birdLanded ? 1 : 0)
                    .offset(y: birdLanded ? 0 : -18)
                    .position(x: tip.x - 20, y: tip.y - 30)
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    private func leafGlyph(revealed: Bool, above: Bool) -> some View {
        let leafSize = CGSize(width: 34, height: 34 * (24.0 / 60.0) * 2.0)
        return ZStack {
            LeafShape().fill(palette.leafFill)
            RibShape().stroke(palette.leafRib, style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }
        .frame(width: leafSize.width, height: leafSize.height)
        .rotationEffect(.degrees(above ? -18 : 18))
        .offset(y: above ? -leafSize.height * 0.5 : leafSize.height * 0.5)
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed ? 1 : 0.6, anchor: .leading)
    }

    // The stem: a gentle upward sweep from the lower-left to the upper-right tip.
    private func stemStart(in size: CGSize) -> CGPoint { CGPoint(x: size.width * 0.14, y: size.height * 0.86) }
    private func stemControl(in size: CGSize) -> CGPoint { CGPoint(x: size.width * 0.5, y: size.height * 0.9) }
    private func stemTip(in size: CGSize) -> CGPoint { CGPoint(x: size.width * 0.82, y: size.height * 0.28) }

    private func stemPoint(at t: CGFloat, in size: CGSize) -> CGPoint {
        let start = stemStart(in: size)
        let control = stemControl(in: size)
        let end = stemTip(in: size)
        let mt = 1 - t
        let x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x
        let y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }
}

/// A quadratic sweep matching ``CeremonyBranch``'s stem geometry, drawn for the
/// grow-in trim.
private struct CeremonyStem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.width * 0.14, y: rect.height * 0.86)
        let control = CGPoint(x: rect.width * 0.5, y: rect.height * 0.9)
        let end = CGPoint(x: rect.width * 0.82, y: rect.height * 0.28)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}
