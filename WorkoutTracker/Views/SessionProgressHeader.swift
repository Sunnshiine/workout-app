import SwiftUI

struct SessionProgressHeader: View {
    let session: Session
    let activeSetID: ActiveSetID?
    let block: Block?
    let currentSession: Session?
    let showsSessionControls: Bool
    let isSessionControlsSyncDisabled: Bool
    let onNavigate: () -> Void
    let onSettings: () -> Void
    let onSync: () -> Void

    init(
        session: Session,
        activeSetID: ActiveSetID?,
        block: Block? = nil,
        currentSession: Session? = nil,
        showsSessionControls: Bool = false,
        isSessionControlsSyncDisabled: Bool = false,
        onNavigate: @escaping () -> Void = {},
        onSettings: @escaping () -> Void = {},
        onSync: @escaping () -> Void = {}
    ) {
        self.session = session
        self.activeSetID = activeSetID
        self.block = block
        self.currentSession = currentSession
        self.showsSessionControls = showsSessionControls
        self.isSessionControlsSyncDisabled = isSessionControlsSyncDisabled
        self.onNavigate = onNavigate
        self.onSettings = onSettings
        self.onSync = onSync
    }

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session, activeSetID: activeSetID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSessionControls {
                HStack {
                    Spacer(minLength: 0)

                    SessionControls(
                        isSyncDisabled: isSessionControlsSyncDisabled,
                        onSettings: onSettings,
                        onSync: onSync
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }

            HStack(spacing: 10) {
                locationLabel

                Spacer()

                Text(presentation.remainingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("session-remaining-count")
            }

            HStack(spacing: 3) {
                ForEach(Array(presentation.segments.enumerated()), id: \.offset) { _, segment in
                    SessionProgressSegment(segment: segment)
                }
            }
            .frame(height: 8)
            .accessibilityLabel("Session progress")
            .accessibilityValue(presentation.progressAccessibilityValue)
            .accessibilityIdentifier("session-progress-rail")
        }
        .padding(.vertical, 2)
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
            .foregroundStyle(.primary)
    }
}

private struct SessionControls: View {
    let isSyncDisabled: Bool
    let onSettings: () -> Void
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("session-controls-settings-button")

            Button(action: onSync) {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(isSyncDisabled)
            .accessibilityIdentifier("session-controls-sync-button")
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session Controls")
        .accessibilityIdentifier("session-controls")
    }
}

private struct SessionProgressSegment: View {
    let segment: SessionProgressSegmentPresentation

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(stroke, lineWidth: strokeWidth)
            }
            .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
    }

    private var fill: Color {
        switch segment.state {
        case .logged:
            Theme.accent
        case .skipped:
            .gray.opacity(0.45)
        case .currentPending:
            .clear
        case .futurePending:
            Theme.progressTrack.opacity(0.85)
        }
    }

    private var stroke: Color {
        switch segment.state {
        case .currentPending:
            Theme.accent
        default:
            .clear
        }
    }

    private var strokeWidth: CGFloat {
        switch segment.state {
        case .currentPending:
            1.25
        default:
            0
        }
    }
}
