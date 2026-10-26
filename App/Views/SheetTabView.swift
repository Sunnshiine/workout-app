import SwiftUI

/// The current Block's Sheet tab read live, one Week at a time: each Day's section as the spreadsheet
/// shows it, raw values under their column letters and beside their row numbers, for checking what
/// the app does not render.
struct SheetTabView: View {
    let read: @MainActor () async throws -> SheetTabSnapshot
    /// The Week shown first, the Block grid's focus Week.
    let focusWeek: Int?

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
            SheetTabGrid(presentation: presentation, focusWeek: focusWeek)
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
    let row: Int
    let column: Int
    let value: String
}

private struct SheetTabGrid: View {
    let presentation: SheetTabGridPresentation

    @Environment(\.themePalette) private var palette
    @State private var week: Int
    @State private var selected: SelectedCell?

    init(presentation: SheetTabGridPresentation, focusWeek: Int?) {
        self.presentation = presentation
        let weekNumbers = presentation.weeks.map(\.number)
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
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        ForEach(days) { day in
                            dayGrid(day)
                        }
                    }
                    .padding(.vertical)
                }
                .accessibilityIdentifier("sheet-tab-grid")
            } else {
                Text("This tab has no Day headers.")
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxHeight: .infinity)
            }
            if let selected {
                cellDetail(selected)
            }
        }
        .onChange(of: week) {
            selected = nil
        }
    }

    private func dayGrid(_ day: SheetTabGridPresentation.Day) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("", width: Theme.sheetRowNumberWidth)
                    ForEach(day.columns, id: \.self) { column in
                        headerCell(SheetTabGridPresentation.columnLetter(column), width: Theme.sheetCellWidth)
                    }
                }
                ForEach(day.rows) { row in
                    HStack(spacing: 0) {
                        headerCell(String(row.number), width: Theme.sheetRowNumberWidth)
                        ForEach(Array(zip(day.columns, row.cells)), id: \.0) { column, value in
                            cell(row: row.number, column: column, value: value)
                        }
                    }
                    .opacity(row.isHidden ? Theme.sheetHiddenRowOpacity : 1)
                }
            }
        }
        .contentMargins(.horizontal, Theme.blockFocusCardPadding, for: .scrollContent)
        .accessibilityIdentifier("sheet-tab-day-\(day.number)")
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(Theme.font(.sheetCell))
            .foregroundStyle(palette.textSecondary)
            .frame(width: width, height: Theme.sheetCellHeight)
            .background(palette.weekCardShade)
            .border(palette.queueStroke, width: Theme.sheetGridline)
    }

    @ViewBuilder
    private func cell(row: Int, column: Int, value: String) -> some View {
        let cell = SelectedCell(row: row, column: column, value: value)
        let isSelected = selected == cell
        if value.isEmpty {
            // Blank cells would bury the filled ones for VoiceOver.
            cellFace(value, isSelected: false).accessibilityHidden(true)
        } else {
            Button {
                selected = isSelected ? nil : cell
            } label: {
                cellFace(value, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet-cell-\(SheetTabGridPresentation.cellReference(row: row, column: column))")
        }
    }

    private func cellFace(_ value: String, isSelected: Bool) -> some View {
        Text(value)
            .font(Theme.font(.sheetCell))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: Theme.sheetCellWidth, height: Theme.sheetCellHeight, alignment: .leading)
            .background(palette.surface)
            .border(
                isSelected ? palette.tileCurrentBorder : palette.queueStroke,
                width: isSelected ? Theme.sheetSelectedCellStroke : Theme.sheetGridline
            )
    }

    private func cellDetail(_ cell: SelectedCell) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SheetTabGridPresentation.cellReference(row: cell.row, column: cell.column))
                .font(Theme.font(.fieldLabel))
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("sheet-tab-cell-reference")
            Text(cell.value)
                .font(Theme.font(.coachNote))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sheet-tab-cell-detail")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(palette.paperBackground.ignoresSafeArea())
        .overlay(alignment: .top) {
            Rectangle().fill(palette.queueStroke).frame(height: Theme.sheetGridline)
        }
    }
}

extension EnvironmentValues {
    /// Reads the current Block's Sheet tab live. Nil where there is no Sheet to read, which hides
    /// the Block grid's View Sheet button.
    @Entry var readBlockSheet: (@MainActor () async throws -> SheetTabSnapshot)?
}
