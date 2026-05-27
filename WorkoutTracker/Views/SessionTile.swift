import SwiftUI

struct SessionTile: View {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState

    var body: some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week \(weekNumber), Day \(dayNumber)")
        .accessibilityValue(accessibilityValue)
    }

    private var backgroundColor: Color {
        switch state {
        case .complete:
            Theme.sessionTileComplete
        case .hasOpenExercises:
            Theme.sessionTileHasOpenExercises
        case .current:
            Theme.sessionTileCurrent
        case .upcoming:
            Theme.sessionTileUpcoming
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .hasOpenExercises, .current:
            Theme.accentDarkText
        case .complete:
            .white
        case .upcoming:
            .white.opacity(0.72)
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .complete:
            "Complete"
        case .hasOpenExercises:
            "Has open exercises"
        case .current:
            "Current"
        case .upcoming:
            "Upcoming"
        }
    }
}
