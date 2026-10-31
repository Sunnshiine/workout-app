import SwiftUI

struct BlockOverviewView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEntryInbox.self) private var entry
    @Environment(\.readBlockSheet) private var readBlockSheet
    @State private var presented: PresentedSurface?

    private enum PresentedSurface: Identifiable {
        case settings
        case sheetTab

        var id: Self { self }
    }

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
                settingsRow
            }
            .padding()
        }
        .sheet(item: $presented) { surface in
            switch surface {
            case .settings:
                SettingsView()
            case .sheetTab:
                if let readBlockSheet {
                    SheetTabView(read: readBlockSheet, currentSession: currentSession?.address)
                        .presentationDetents([.large])
                }
            }
        }
        .onChange(of: entry.coverClosings) {
            presented = nil
            dismiss()
        }
        .background {
            palette.paperBackground
                .overlay { palette.lighting.pageSunbeam?.gradientView }
                .ignoresSafeArea()
        }
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if readBlockSheet != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("View Sheet", systemImage: "tablecells") {
                        presented = .sheetTab
                    }
                    .accessibilityIdentifier("block-overview-view-sheet")
                }
            }
        }
    }

    private var settingsRow: some View {
        Button {
            presented = .settings
        } label: {
            Image(systemName: "gearshape")
                .font(Theme.font(.queuePill))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("block-overview-settings-row")
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
        .background(palette.lighting.focusCardFill, in: .rect(cornerRadius: Theme.Radius.focusCard))
        .themeElevation(palette.lighting.focusCardElevation, in: .rect(cornerRadius: Theme.Radius.focusCard))
        .padding(.vertical, Theme.ringReach(of: palette.lighting.focusCardElevation))
    }

    // MARK: - Collapsed week — an elevated card in shade with a mini day-strip

    private func collapsedWeek(_ week: BlockOverviewWeekPresentation) -> some View {
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

            // Each mini tile is its own tap target so it routes to the day the athlete
            // aimed at. A single card-wide button routed every tap to the Week's first
            // available day (its day 1) — the reported "day 4 opens day 1" regression.
            HStack(spacing: Theme.blockTileMiniSpacing) {
                ForEach(week.tiles, id: \.accessibilityIdentifier) { tile in
                    dayTile(tile, variant: .mini)
                }
            }
        }
        .padding(Theme.blockWeekCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.weekCardShade, in: .rect(cornerRadius: Theme.Radius.card))
        .themeElevation(palette.lighting.weekCardElevation, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .contain)
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
                show(tile.address)
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

    private func show(_ address: SessionAddress) {
        workout.show(address)
        dismiss()
    }
}
