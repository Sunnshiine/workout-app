import SwiftUI

struct BlockOverviewView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let block: Block
    let currentSession: Session?

    private var presentation: BlockOverviewPresentation {
        BlockOverviewPresentation(block: block, currentSession: currentSession)
    }

    private func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.sessionTileSpacing), count: count)
    }

    var body: some View {
        let presentation = presentation
        ScrollView {
            LazyVGrid(columns: columns(count: presentation.columnCount), spacing: Theme.sessionTileSpacing) {
                ForEach(presentation.tiles, id: \.accessibilityIdentifier) { tile in
                    if tile.state == .unavailable {
                        SessionTile(
                            weekNumber: tile.weekNumber,
                            dayNumber: tile.dayNumber,
                            state: tile.state
                        )
                        .accessibilityIdentifier(tile.accessibilityIdentifier)
                    } else {
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
            }
            .padding()
        }
        .background(palette.gradient.ignoresSafeArea())
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func show(week: Int, day: Int) {
        workout.show(week: week, day: day)
        dismiss()
    }
}
