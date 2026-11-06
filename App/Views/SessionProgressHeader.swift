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

            SessionSyncStatusLabel()

            Text(presentation.remainingText)
                .themeFont(.runlineSecondary)
                .lineLimit(1)
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
        ViewThatFits(in: .horizontal) {
            locationLine(presentation.runlineText)
            locationLine(presentation.compactRunlineText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.runlineText)
    }

    private func locationLine(_ text: String) -> some View {
        Text("\(Image(systemName: "calendar")) \(text)")
            .themeFont(.runline)
            .lineLimit(1)
            .minimumScaleFactor(Theme.TypeRole.runline.denseFloorScale)
            .foregroundStyle(palette.textSecondary)
    }
}

/// Syncing, Offline, and `N unsynced` sit beside the count, so the athlete keeps their place while
/// the state stays honest (PRODUCT.md, Trust the round-trip).
private struct SessionSyncStatusLabel: View {
    @Environment(SyncCoordinator.self) private var sync: SyncCoordinator?
    @Environment(\.themePalette) private var palette

    private var presentation: SyncStatusBannerPresentation? {
        sync.flatMap { SyncStatusBannerPresentation(outcome: $0.outcome, isSyncing: $0.isSyncing) }
            .flatMap { $0.isBrief ? $0 : nil }
    }

    var body: some View {
        Group {
            if let presentation {
                Text(presentation.text)
                    .themeFont(.runlineSecondary)
                    .lineLimit(1)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize()
                    .transition(.opacity)
                    .accessibilityLabel(presentation.accessibilityLabel)
            }
        }
        .animation(.smooth(duration: 0.18), value: presentation?.text)
    }
}
