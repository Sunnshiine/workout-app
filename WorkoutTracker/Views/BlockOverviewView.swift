import SwiftUI

/// The Block grid — the focus week. One Week (the one holding the Current Session) stands in
/// morning light with a glowing rim; every other Week collapses to a card in shade carrying a
/// summary and a mini day-strip. Hierarchy is **light and shade at one elevation**, and the
/// sunlit hour (page sunbeam, the focus card's rim, the current tile's `sunGlow`, tile top-light)
/// is the page's only delight — no branches, no bird (DESIGN.md §5.5).
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
        .background {
            // The living paper under the page sunbeam — the warm morning falling from the
            // top-right, the page's single wash of Day light. The sunlit hour is a Day delight;
            // at Night the room re-lights on the paper's own lamp pool alone (One Glow Rule).
            palette.paperBackground
                .overlay {
                    if palette.appearance == .day {
                        Theme.LightKit.pageSunbeam.gradientView
                    }
                }
                .ignoresSafeArea()
        }
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Focus week — the one week in morning light with the glowing rim

    private func focusWeek(_ week: BlockOverviewWeekPresentation, columnCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.blockFocusCardPadding - 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.weekNumber)")
                    .font(Theme.font(.statsValue))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text(week.summary)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            }

            LazyVGrid(columns: columns(count: columnCount), spacing: Theme.blockTileSpacing) {
                ForEach(week.tiles, id: \.accessibilityIdentifier) { tile in
                    dayTile(tile, variant: .full)
                }
            }
        }
        .padding(Theme.blockFocusCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // By Day the focus card stands in morning light — the dedicated cream fill under the cream
        // glow rim (the sunlit hour). At Night the room re-lights: a quiet lifted sage surface
        // distinguished by the inset cream border-as-light, no cream bloom (Room Re-lights Rule).
        .background(focusCardFill, in: .rect(cornerRadius: Theme.Radius.focusCard))
        .themeElevation(focusCardElevation, in: .rect(cornerRadius: Theme.Radius.focusCard))
    }

    private var focusCardFill: Color {
        palette.appearance == .day ? Theme.LightKit.focusCardFill : palette.surface
    }

    private var focusCardElevation: [Theme.BoxShadow] {
        palette.appearance == .day ? Theme.LightKit.focusCardGlowRim : palette.surfaceShadow
    }

    // MARK: - Collapsed week — an elevated card in shade with a mini day-strip

    private func collapsedWeek(_ week: BlockOverviewWeekPresentation) -> some View {
        Button {
            openFirstAvailableDay(in: week)
        } label: {
            VStack(alignment: .leading, spacing: Theme.blockWeekCardPadding - 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(week.weekNumber)")
                        .font(Theme.font(.fieldLabel))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(week.collapsedSummary)
                        .font(Theme.font(.queuePill))
                        .foregroundStyle(palette.textSecondary)
                }

                HStack(spacing: Theme.blockTileMiniSpacing) {
                    ForEach(week.tiles, id: \.accessibilityIdentifier) { tile in
                        SessionTile(state: tile.state, fillQuarters: tile.fillQuarters, variant: .mini)
                    }
                }
            }
            .padding(Theme.blockWeekCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.weekCardShade, in: .rect(cornerRadius: Theme.Radius.card))
            .themeElevation(Theme.LightKit.cardLow, in: .rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week \(week.weekNumber)")
        .accessibilityValue("\(week.collapsedSummary) Sessions complete")
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
