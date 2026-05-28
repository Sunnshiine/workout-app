import SwiftUI

struct BlockOverviewView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.dismiss) private var dismiss

    let block: Block
    let currentSession: Session?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.sessionTileSpacing),
        count: 4
    )

    private var presentation: BlockOverviewPresentation {
        BlockOverviewPresentation(block: block, currentSession: currentSession)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.sessionTileSpacing) {
                ForEach(presentation.tiles, id: \.accessibilityIdentifier) { tile in
                    Button {
                        show(week: tile.weekNumber, day: tile.dayNumber)
                    } label: {
                        SessionTile(
                            weekNumber: tile.weekNumber,
                            dayNumber: tile.dayNumber,
                            state: tile.state
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tile.accessibilityLabel)
                    .accessibilityValue(tile.accessibilityValue)
                    .accessibilityIdentifier(tile.accessibilityIdentifier)
                }
            }
            .padding()
        }
        .background(Theme.gradient.ignoresSafeArea())
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func show(week: Int, day: Int) {
        workout.show(week: week, day: day)
        dismiss()
    }
}
