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
        Array(repeating: GridItem(.flexible(), spacing: Theme.blockTileSpacing), count: count)
    }

    var body: some View {
        let presentation = presentation
        ScrollView {
            VStack(spacing: Theme.blockTileSpacing + 4) {
                ForEach(presentation.weeks, id: \.weekNumber) { week in
                    if week.isFocus {
                        focusWeek(week, columnCount: presentation.columnCount)
                    } else {
                        collapsedWeek(week)
                    }
                }
            }
            .padding()
        }
        .background(palette.paperBackground.ignoresSafeArea())
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Focus week — the one week in morning light with the glowing rim

    private func focusWeek(_ week: BlockOverviewWeekPresentation, columnCount: Int) -> some View {
        LazyVGrid(columns: columns(count: columnCount), spacing: Theme.blockTileSpacing) {
            ForEach(week.tiles, id: \.accessibilityIdentifier) { tile in
                dayTile(tile, variant: .full)
            }
        }
        .padding(Theme.blockFocusCardPadding)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.focusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.focusCard)
                .stroke(palette.tileCurrentBorder.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: palette.tileCurrentBorder.opacity(0.22), radius: Theme.blockFocusGlowRadius)
    }

    // MARK: - Collapsed week — an elevated card in shade with a mini day-strip

    private func collapsedWeek(_ week: BlockOverviewWeekPresentation) -> some View {
        Button {
            openFirstAvailableDay(in: week)
        } label: {
            HStack(spacing: Theme.blockWeekCardPadding) {
                Text("Week \(week.weekNumber)")
                    .font(Theme.font(.fieldLabel))
                    .foregroundStyle(palette.textSecondary)

                HStack(spacing: Theme.blockTileMiniSpacing) {
                    ForEach(week.tiles, id: \.accessibilityIdentifier) { tile in
                        SessionTile(state: tile.state, fillQuarters: tile.fillQuarters, variant: .mini)
                            .frame(width: 22)
                    }
                }

                Spacer(minLength: 0)

                Text(week.summary)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Theme.blockWeekCardPadding)
            .frame(maxWidth: .infinity)
            .background(palette.weekCardShade, in: .rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week \(week.weekNumber)")
        .accessibilityValue("\(week.summary) Sessions complete")
        .accessibilityIdentifier("week-card-W\(week.weekNumber)")
    }

    // MARK: - Day tile

    @ViewBuilder
    private func dayTile(_ tile: BlockOverviewTilePresentation, variant: SessionTile.Variant) -> some View {
        if tile.state == .unavailable {
            // An empty bed is not tappable — nothing is uploaded to open.
            SessionTile(state: tile.state, fillQuarters: tile.fillQuarters, variant: variant)
                .accessibilityElement()
                .accessibilityLabel(tile.accessibilityLabel)
                .accessibilityValue(tile.accessibilityValue)
                .accessibilityIdentifier(tile.accessibilityIdentifier)
        } else {
            Button {
                show(week: tile.weekNumber, day: tile.dayNumber)
            } label: {
                SessionTile(state: tile.state, fillQuarters: tile.fillQuarters, variant: variant)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.accessibilityLabel)
            .accessibilityValue(tile.accessibilityValue)
            .accessibilityIdentifier(tile.accessibilityIdentifier)
        }
    }

    private func openFirstAvailableDay(in week: BlockOverviewWeekPresentation) {
        guard let day = week.tiles.first(where: { $0.state != .unavailable }) else { return }
        show(week: day.weekNumber, day: day.dayNumber)
    }

    private func show(week: Int, day: Int) {
        workout.show(week: week, day: day)
        dismiss()
    }
}
