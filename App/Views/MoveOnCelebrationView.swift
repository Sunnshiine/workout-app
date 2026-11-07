import SwiftUI

struct MoveOnCelebrationView: View {
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var isArriving: Bool
    @State private var presentation: MoveOnCelebrationPresentation
    @AccessibilityFocusState private var isTitleFocused: Bool

    init(
        session: Session,
        quoteText: String? = nil,
        arrivesOverTheStage: Bool,
        onDismiss: @escaping () -> Void
    ) {
        _isArriving = State(initialValue: arrivesOverTheStage)
        _presentation = State(
            initialValue: MoveOnCelebrationPresentation(session: session, quoteText: quoteText)
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            palette.paperBackground
                .ignoresSafeArea()
                .opacity(isArriving ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: isArriving)

            // At an accessibility text size the composition outgrows the screen, so it scrolls and
            // Move On stays pinned under it, in reach without a scroll.
            ViewThatFits(in: .vertical) {
                column(endingInContinue: true)
                VStack(spacing: 0) {
                    ScrollView { column(endingInContinue: false) }
                    continueButton
                }
            }
            // The stage's grid: the header rides the session header's row, and Continue lands where
            // the completion stage's Move On sat, so the press stays on the button it becomes.
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 9)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityIdentifier("move-on-celebration")
            // The stage stays in the tree under this overlay, so the trait keeps VoiceOver off it.
            .accessibilityAddTraits(.isModal)
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .onAppear { isArriving = false }
        .task {
            HapticPlayer.shared.play(.moveOn)
            isTitleFocused = true
        }
    }

    private func column(endingInContinue: Bool) -> some View {
        VStack(spacing: 0) {
            // Arrives once the paper has covered the stage, so no title draws over another.
            Group {
                header

                Spacer(minLength: 12)

                Text(presentation.titleText)
                    .themeFont(.ceremonyTitle)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                    .accessibilityIdentifier("move-on-celebration-title")

                // The bird perches above the branch's frame, so the air keeps it off the title.
                CeremonyBranch()
                    .padding(.top, 28)

                Text(presentation.quoteText)
                    .themeFont(.coachNote)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.top, 18)
                    .accessibilityIdentifier("move-on-celebration-coach-line")

                statsRow
                    .padding(.top, 28)

                Spacer(minLength: 12)
            }
            .opacity(isArriving ? 0 : 1)
            .animation(.easeOut(duration: 0.2).delay(0.1), value: isArriving)

            if endingInContinue {
                continueButton
            }
        }
    }

    private var header: some View {
        contextText
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }

    private var contextText: some View {
        Text("\(Image(systemName: "calendar")) \(presentation.contextText)")
            .accessibilityLabel(presentation.contextText)
            .themeFont(.runline)
            .foregroundStyle(palette.textPrimary)
            .accessibilityIdentifier("move-on-celebration-context")
    }

    // Side by side, the stats truncate at an accessibility text size, so they stack.
    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { stats }
            VStack(spacing: 10) { stats }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
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
            // Move On's own capsule, opaque from the first frame: only its label changes under the press.
            Text("Move On")
                .opacity(isArriving ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: isArriving)
                .overlay {
                    Image(systemName: "sunrise")
                        .imageScale(.large)
                        .opacity(isArriving ? 0 : 1)
                        .animation(.easeOut(duration: 0.16).delay(0.08), value: isArriving)
                }
                .logCapsuleMetrics()
                .foregroundStyle(palette.actionText)
                .background(palette.actionFill, in: .capsule)
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
                .accessibilityIdentifier("move-on-celebration-\(identifierKey)-label")
        }
        .frame(maxWidth: .infinity)
    }
}
