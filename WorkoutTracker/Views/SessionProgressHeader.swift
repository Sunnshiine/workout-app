import SwiftUI

struct SessionProgressHeader: View {
    let session: Session
    let activeSetID: ActiveSetID?
    let block: Block?
    let currentSession: Session?
    let onNavigate: () -> Void

    init(
        session: Session,
        activeSetID: ActiveSetID?,
        block: Block? = nil,
        currentSession: Session? = nil,
        onNavigate: @escaping () -> Void = {}
    ) {
        self.session = session
        self.activeSetID = activeSetID
        self.block = block
        self.currentSession = currentSession
        self.onNavigate = onNavigate
    }

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session, activeSetID: activeSetID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                locationLabel

                Spacer()

                Text(presentation.remainingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 3) {
                ForEach(Array(presentation.segments.enumerated()), id: \.offset) { _, segment in
                    SessionProgressSegment(segment: segment)
                }
            }
            .frame(height: 8)
            .accessibilityLabel("Session progress")
            .accessibilityValue(presentation.progressAccessibilityValue)
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
