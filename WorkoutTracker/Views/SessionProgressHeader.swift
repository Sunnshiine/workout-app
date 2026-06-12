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
    @Namespace private var focusMarkerNamespace

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
        SessionProgressHeaderPresentation(session: session, activeSetID: activeSetID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                locationLabel

                Spacer()

                trailingHeaderControl
            }
            .frame(minHeight: 32)

            HStack(spacing: 3) {
                ForEach(Array(presentation.segments.enumerated()), id: \.offset) { _, segment in
                    SessionProgressSegment(
                        segment: segment,
                        focusMarkerNamespace: focusMarkerNamespace,
                        usesTravelingFocusMarker: !reduceMotion
                    )
                }
            }
            .frame(height: 8)
            .offset(y: -2)
            .accessibilityLabel("Session progress")
            .accessibilityValue(presentation.progressAccessibilityValue)
            .accessibilityIdentifier("session-progress-rail")
        }
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
        Text(presentation.locationText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.valueText)
    }

    private var trailingHeaderControl: some View {
        ZStack(alignment: .trailing) {
            Text(presentation.remainingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
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
                    .font(.system(size: 18, weight: .semibold))
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

private struct SessionProgressSegment: View {
    let segment: SessionProgressSegmentPresentation
    let focusMarkerNamespace: Namespace.ID
    let usesTravelingFocusMarker: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay {
                if segment.state == .currentPending {
                    focusMarker
                }
            }
            .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
    }

    private var fill: Color {
        switch segment.state {
        case .logged:
            palette.accent
        case .skipped:
            .gray.opacity(0.45)
        case .currentPending:
            .clear
        case .futurePending:
            palette.progressTrack.opacity(0.85)
        }
    }

    @ViewBuilder
    private var focusMarker: some View {
        let marker = RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(palette.accent, lineWidth: 1.25)

        if usesTravelingFocusMarker {
            marker.matchedGeometryEffect(id: "session-progress-focus-marker", in: focusMarkerNamespace)
        } else {
            marker
        }
    }
}
