import SwiftUI

/// The current Block's Sheet tab read live, one Week at a time: each Day's section as the spreadsheet
/// shows it, raw values under their column letters, for checking what the app does not render.
struct SheetTabView: View {
    let read: @MainActor () async throws -> SheetTabSnapshot
    /// Its Week opens first and its Day stands in morning light, as on the Block grid.
    let currentSession: SessionAddress?

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var load = Load.loading

    private enum Load {
        case loading
        case loaded(SheetTabGridPresentation)
        case failed
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.paperBackground.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", systemImage: "checkmark") {
                            dismiss()
                        }
                        .accessibilityIdentifier("sheet-tab-done")
                    }
                }
        }
        .task { await reload() }
    }

    private var title: String {
        guard case .loaded(let presentation) = load else { return "Sheet" }
        return presentation.tab
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            ProgressView()
        case .loaded(let presentation):
            SheetTabGrid(presentation: presentation, currentSession: currentSession)
        case .failed:
            VStack(spacing: Theme.cardSpacing) {
                Text("Couldn't reach the Sheet. Check your connection and try again.")
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await reload() }
                }
                .accessibilityIdentifier("sheet-tab-retry")
            }
            .padding()
        }
    }

    private func reload() async {
        load = .loading
        do {
            load = .loaded(SheetTabGridPresentation(try await read()))
        } catch {
            load = .failed
        }
    }
}

private struct SelectedCell: Equatable {
    let row: SheetTabGridPresentation.Row
    let column: SheetTabGridPresentation.Column
    let value: String

    var reference: String { SheetTabGridPresentation.cellReference(row: row.number, column: column.index) }
}

private struct SheetTabGrid: View {
    let presentation: SheetTabGridPresentation
    let currentSession: SessionAddress?

    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var week: Int
    @State private var selected: SelectedCell?
    @State private var cardWidth: CGFloat = 0

    init(presentation: SheetTabGridPresentation, currentSession: SessionAddress?) {
        self.presentation = presentation
        self.currentSession = currentSession
        let weekNumbers = presentation.weeks.map(\.number)
        let focusWeek = currentSession.map(\.week)
        _week = State(initialValue: focusWeek.flatMap { weekNumbers.contains($0) ? $0 : nil } ?? weekNumbers.first ?? 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation.weeks.count > 1 {
                Picker("Week", selection: $week) {
                    ForEach(presentation.weeks) { week in
                        Text("Week \(week.number)").tag(week.number)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier("sheet-tab-week-picker")
            }
            if let days = presentation.weeks.first(where: { $0.number == week })?.days {
                ScrollView(.vertical) {
                    VStack(spacing: Theme.blockTileSpacing + 4) {
                        ForEach(days) { day in
                            dayCard(day, isCurrent: currentSession == SessionAddress(week: week, day: day.number))
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { cardWidth = $0 }
                    .padding()
                    .id(week)
                    .transition(.opacity)
                }
                .accessibilityIdentifier("sheet-tab-grid")
            } else {
                Text("This tab has no Day headers.")
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxHeight: .infinity)
            }
        }
        .animation(.smooth(duration: 0.2), value: week)
        .safeAreaInset(edge: .bottom) {
            if let selected {
                cellDetail(selected)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: week) {
            selected = nil
        }
    }

    // MARK: - Day card: the Block grid's light and shade, the current Session's Day in morning light

    private func dayCard(_ day: SheetTabGridPresentation.Day, isCurrent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: isCurrent ? Theme.Radius.focusCard : Theme.Radius.card)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.title.isEmpty ? "Day \(day.number)" : day.title)
                    .font(Theme.font(.heading))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text(day.date)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Theme.blockFocusCardPadding)

            if day.rows.isEmpty {
                Text("Not uploaded")
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Theme.blockFocusCardPadding)
            } else {
                let widths = SheetTabGridPresentation.columnWidths(
                    day.columns.map(\.role),
                    fitting: cardWidth - 2 * Theme.blockFocusCardPadding
                )
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader(day, widths: widths)
                        ForEach(day.rows) { row in
                            rowView(row, in: day, widths: widths)
                        }
                    }
                    .padding(.horizontal, Theme.blockFocusCardPadding)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .padding(.vertical, Theme.blockFocusCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? palette.lighting.focusCardFill : palette.weekCardShade, in: shape)
        .themeElevation(isCurrent ? palette.lighting.focusCardElevation : Theme.LightKit.cardLow, in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-tab-day-\(day.number)")
    }

    private func columnHeader(_ day: SheetTabGridPresentation.Day, widths: [Double]) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(zip(day.columns, widths)), id: \.0.index) { column, width in
                VStack(alignment: .leading, spacing: 1) {
                    Text(column.label)
                        .font(Theme.font(.cadence))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(column.letter)
                        .font(Theme.font(.cadence))
                        .foregroundStyle(palette.textSecondary.opacity(0.6))
                }
                .padding(.horizontal, Theme.sheetCellInset)
                .frame(width: width, alignment: .leading)
            }
        }
        .padding(.bottom, 4)
    }

    private func rowView(
        _ row: SheetTabGridPresentation.Row,
        in day: SheetTabGridPresentation.Day,
        widths: [Double]
    ) -> some View {
        // Cells sit on their first line, so a wrapped value hangs down like a wrapped Sheet cell.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(zip(zip(day.columns, row.cells), widths)), id: \.0.0.index) { cell, width in
                self.cell(SelectedCell(row: row, column: cell.0, value: cell.1), width: width)
            }
        }
        .frame(minHeight: Theme.sheetRowHeight)
        .overlay(alignment: .top) {
            if row.startsExercise {
                Rectangle().fill(palette.queueStroke).frame(height: Theme.sheetHairline)
            }
        }
        .opacity(row.isHidden ? Theme.sheetHiddenRowOpacity : 1)
    }

    @ViewBuilder
    private func cell(_ cell: SelectedCell, width: Double) -> some View {
        let isSelected = selected == cell
        if cell.value.isEmpty {
            // Blank cells would bury the filled ones for VoiceOver.
            cellFace(cell, width: width, isSelected: false).accessibilityHidden(true)
        } else {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    selected = isSelected ? nil : cell
                }
            } label: {
                cellFace(cell, width: width, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet-cell-\(cell.reference)")
        }
    }

    private func cellFace(_ cell: SelectedCell, width: Double, isSelected: Bool) -> some View {
        let leadsExercise = cell.column.role == .name && cell.row.startsExercise
        return Text(cell.value)
            .font(Theme.font(leadsExercise ? .runline : .sheetCell))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(Theme.sheetCellLineLimit)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.sheetCellInset)
            .padding(.vertical, Theme.sheetCellVerticalInset)
            .frame(width: width, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.mini)
                        .fill(palette.tileCurrentFill)
                        .strokeBorder(palette.tileCurrentBorder, lineWidth: Theme.sheetSelectedCellStroke)
                }
            }
            .contentShape(.rect)
    }

    // MARK: - Cell detail: the whole value a truncated cell holds

    private func cellDetail(_ cell: SelectedCell) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cell.reference)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityIdentifier("sheet-tab-cell-reference")
                if !cell.column.label.isEmpty {
                    Text(cell.column.label)
                        .font(Theme.font(.fieldLabel))
                        .foregroundStyle(palette.textSecondary)
                }
                if cell.row.isHidden {
                    Text("Hidden in the Sheet")
                        .font(Theme.font(.fieldLabel))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Text(cell.value)
                .font(Theme.font(.coachNote))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sheet-tab-cell-detail")
        }
        .padding(Theme.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.lighting.focusCardFill, in: shape)
        // Night's card fill is translucent; the paper keeps the Day cards from showing through.
        .background(palette.paperBackground.clipShape(shape))
        .themeElevation(palette.lighting.focusCardElevation, in: shape)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

extension EnvironmentValues {
    /// Reads the current Block's Sheet tab live. Nil where there is no Sheet to read, which hides
    /// the Block grid's View Sheet button.
    @Entry var readBlockSheet: (@MainActor () async throws -> SheetTabSnapshot)?
}
