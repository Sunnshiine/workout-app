import SwiftUI

struct SessionProgressHeader: View {
    let session: Session
    let block: Block?
    let currentSession: Session?
    let onNavigate: () -> Void
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: Session,
        block: Block? = nil,
        currentSession: Session? = nil,
        onNavigate: @escaping () -> Void = {}
    ) {
        self.session = session
        self.block = block
        self.currentSession = currentSession
        self.onNavigate = onNavigate
    }

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session, block: block)
    }

    var body: some View {
        HStack(spacing: 10) {
            locationLabel

            Spacer()

            Text(presentation.remainingText)
                .themeFont(.runlineSecondary)
                .contentTransition(
                    reduceMotion ? .opacity : .numericText(value: Double(presentation.remainingSetCount))
                )
                // Its own spring, not the stage's momentumFlow or skipFadeUp, so a log and a skip roll alike.
                .animation(.snappy(duration: 0.2), value: presentation.remainingSetCount)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("session-remaining-count")
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .contain)
        .accessibilityValue(presentation.progressAccessibilityValue)
    }

    @ViewBuilder
    private var locationLabel: some View {
        if let block {
            NavigationLink {
                BlockOverviewView(block: block, currentSession: currentSession)
            } label: {
                locationLabelText
                    .hitOutset(HitOutset.textLine)
            }
            .buttonStyle(.plain)
            .givingBackHitOutset(HitOutset.textLine)
            .simultaneousGesture(TapGesture().onEnded(onNavigate))
            .accessibilityLabel(presentation.locationActionAccessibilityLabel)
            .accessibilityIdentifier("session-location-button")
        } else {
            locationLabelText
        }
    }

    private var locationLabelText: some View {
        Text("\(Image(systemName: "calendar")) \(presentation.runlineText)")
            .accessibilityLabel(presentation.runlineText)
            .themeFont(.runline)
            .foregroundStyle(palette.textSecondary)
    }
}
