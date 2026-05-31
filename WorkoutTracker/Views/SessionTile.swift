import SwiftUI

struct SessionTile: View {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if state == .complete || state == .unavailable {
                tileContent
            } else {
                tileContent
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week \(weekNumber), Day \(dayNumber)")
        .accessibilityValue(state.accessibilityValue)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Week \(weekNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(foregroundStyle.opacity(0.78))

            Text("Day \(dayNumber)")
                .font(.title3.weight(.bold))
                .foregroundStyle(foregroundStyle)

            Spacer(minLength: 0)

            if state == .unavailable {
                Label("Not uploaded", systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(foregroundStyle)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.sessionTileMinHeight, alignment: .topLeading)
        .padding(12)
        .background(backgroundColor, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.sessionTileCornerRadius)
                .stroke(borderColor, lineWidth: borderWidth)
        }
        .opacity(state == .unavailable ? Theme.sessionTileUnavailableOpacity : 1)
    }

    private var backgroundColor: Color {
        switch state {
        case .complete:
            palette.sessionTileComplete
        case .current, .incomplete:
            palette.sessionTileIncomplete
        case .unavailable:
            palette.sessionTileUnavailable
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .current:
            palette.accent
        case .complete:
            palette.sessionTileCompleteText
        case .incomplete:
            palette.sessionTileIncompleteText
        case .unavailable:
            palette.sessionTileUnavailableText
        }
    }

    private var borderColor: Color {
        switch state {
        case .current:
            palette.accent
        case .incomplete:
            palette.sessionTileRestingBorder
        case .complete, .unavailable:
            .clear
        }
    }

    private var borderWidth: CGFloat {
        switch state {
        case .current:
            Theme.sessionTileCurrentBorderWidth
        case .complete, .incomplete, .unavailable:
            1
        }
    }
}
