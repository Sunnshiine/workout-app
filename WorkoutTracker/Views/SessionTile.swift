import SwiftUI

struct SessionTile: View {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState

    var body: some View {
        Group {
            if state == .complete {
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
        }
        .frame(maxWidth: .infinity, minHeight: Theme.sessionTileMinHeight, alignment: .topLeading)
        .padding(12)
        .background(backgroundColor, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.sessionTileCornerRadius)
                .stroke(borderColor, lineWidth: borderWidth)
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .complete:
            Theme.sessionTileComplete
        case .current, .incomplete:
            Theme.sessionTileIncomplete
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .current:
            Theme.sessionTileCurrentBorder
        case .complete:
            .white
        case .incomplete:
            .white.opacity(0.64)
        }
    }

    private var borderColor: Color {
        switch state {
        case .current:
            Theme.sessionTileCurrentBorder
        case .incomplete:
            .white.opacity(0.10)
        case .complete:
            .clear
        }
    }

    private var borderWidth: CGFloat {
        switch state {
        case .current:
            Theme.sessionTileCurrentBorderWidth
        case .complete, .incomplete:
            1
        }
    }
}
