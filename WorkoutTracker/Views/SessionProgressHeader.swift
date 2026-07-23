import SwiftUI

struct SessionProgressHeader: View {
    let session: Session
    let activeSetID: ActiveSetID?
    let block: Block?
    let currentSession: Session?
    let sessionSettingsOverpullState: SessionSettingsOverpullState
    let onNavigate: () -> Void
    let onSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette

    init(
        session: Session,
        activeSetID: ActiveSetID?,
        block: Block? = nil,
        currentSession: Session? = nil,
        sessionSettingsOverpullState: SessionSettingsOverpullState = .hidden,
        onNavigate: @escaping () -> Void = {},
        onSettings: @escaping () -> Void = {}
    ) {
        self.session = session
        self.activeSetID = activeSetID
        self.block = block
        self.currentSession = currentSession
        self.sessionSettingsOverpullState = sessionSettingsOverpullState
        self.onNavigate = onNavigate
        self.onSettings = onSettings
    }

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session, activeSetID: activeSetID, block: block)
    }

    // The plain header runline (ledger §4.3, picks session-stage-a/-d): a
    // left-aligned `Block · Week · Day` line with `N Sets left` on the right. The
    // segmented progress rail is retired — the branch carries progress as flora.
    var body: some View {
        HStack(spacing: 10) {
            locationLabel

            Spacer()

            trailingHeaderControl
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .contain)
        .accessibilityValue(presentation.progressAccessibilityValue)
    }

    private var sessionControlsOpacity: Double {
        if reduceMotion {
            return Double(sessionSettingsOverpullState.progress)
        }
        return Double(0.35 + (0.65 * sessionSettingsOverpullState.progress))
    }

    private var sessionControlsScale: CGFloat {
        if reduceMotion {
            return 0.98 + (0.02 * sessionSettingsOverpullState.progress)
        }
        return 0.88 + (0.12 * sessionSettingsOverpullState.progress)
    }

    private var sessionControlsOffset: CGFloat {
        reduceMotion ? 0 : 10 * (1 - sessionSettingsOverpullState.progress)
    }

    @ViewBuilder
    private var locationLabel: some View {
        if let block {
            NavigationLink {
                BlockOverviewView(block: block, currentSession: currentSession)
            } label: {
                locationLabelText
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded(onNavigate))
            .accessibilityLabel(presentation.locationActionAccessibilityLabel)
            .accessibilityIdentifier("session-location-button")
        } else {
            locationLabelText
        }
    }

    private var locationLabelText: some View {
        Text(presentation.runlineText)
            .font(Theme.font(.runline))
            .foregroundStyle(palette.textSecondary)
    }

    private var trailingHeaderControl: some View {
        ZStack(alignment: .trailing) {
            Text(presentation.remainingText)
                .font(Theme.font(.runlineSecondary))
                .foregroundStyle(palette.textSecondary)
                .opacity(sessionSettingsOverpullState.isVisible ? 0 : 1)
                .accessibilityHidden(sessionSettingsOverpullState.isVisible)
                .accessibilityIdentifier("session-remaining-count")

            if sessionSettingsOverpullState.isVisible {
                SessionControls(onSettings: onSettings)
                    .opacity(sessionControlsOpacity)
                    .scaleEffect(sessionControlsScale, anchor: .center)
                    .offset(y: sessionControlsOffset)
            }
        }
        .frame(minHeight: 32, alignment: .trailing)
    }
}

private struct SessionControls: View {
    let onSettings: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(Theme.font(.logCapsule))
                    .foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32)
            }
            // Plain on purpose: the gear sits inside the header's glass capsule, and a nested
            // glass button renders a circular halo that overflows the capsule corner on device.
            // The snapshot harness composites glass as transparent, so only on-simulator
            // screenshots can verify this.
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .padding(6)
            .contentShape(Rectangle())
            .padding(-6)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("session-controls-settings-button")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session Controls")
        .accessibilityIdentifier("session-controls")
    }
}
