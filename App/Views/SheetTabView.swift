import SwiftUI

/// The current Block's Sheet tab as the spreadsheet shows it, read live: raw values under column
/// letters and beside row numbers, for checking what the app does not render.
struct SheetTabView: View {
    let read: @MainActor () async throws -> SheetTabSnapshot
    /// The Week the grid scrolls to on load, the Block grid's focus Week.
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

private struct CellPosition: Equatable {
    let row: Int
    let column: Int
}

private struct SheetTabGrid: View {
    let presentation: SheetTabGridPresentation
    let focusWeek: Int?

    @Environment(\.themePalette) private var palette
    @State private var selected: CellPosition?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(presentation.rows) { row in
                                rowView(row)
                            }
                        } header: {
                            columnHeader
                        }
                    }
                }
                .accessibilityIdentifier("sheet-tab-grid")
                .onAppear {
                    guard let row = focusWeek.flatMap({ presentation.weekHeaderRows[$0] }) else { return }
                    // The pinned column letters cover the top row, so land the row above it there.
                    proxy.scrollTo(max(row - 1, 1), anchor: .topLeading)
                }
            }
            if let selected {
                cellDetail(selected)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            headerCell("", width: Theme.sheetRowNumberWidth)
            ForEach(presentation.columns, id: \.self) { letter in
                headerCell(letter, width: Theme.sheetCellWidth)
            }
        }
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(Theme.font(.sheetCell))
            .foregroundStyle(palette.textSecondary)
            .frame(width: width, height: Theme.sheetCellHeight)
            .background(palette.weekCardShade)
            .border(palette.queueStroke, width: Theme.sheetGridline)
    }

    private func rowView(_ row: SheetTabGridPresentation.Row) -> some View {
        HStack(spacing: 0) {
            headerCell(String(row.number), width: Theme.sheetRowNumberWidth)
            ForEach(row.cells.indices, id: \.self) { column in
                cell(row: row, column: column)
            }
        }
        .opacity(row.isHidden ? Theme.sheetHiddenRowOpacity : 1)
        .id(row.number)
    }

    @ViewBuilder
    private func cell(row: SheetTabGridPresentation.Row, column: Int) -> some View {
        let value = row.cells[column]
        let position = CellPosition(row: row.number, column: column)
        let isSelected = selected == position
        if value.isEmpty {
            // Thousands of blank cells would bury the filled ones for VoiceOver.
            cellFace(value, isSelected: false).accessibilityHidden(true)
        } else {
            Button {
                selected = isSelected ? nil : position
            } label: {
                cellFace(value, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet-cell-\(SheetTabGridPresentation.cellReference(row: row.number, column: column))")
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

    private func cellDetail(_ position: CellPosition) -> some View {
        let value = presentation.rows[position.row - 1].cells[position.column]
        return VStack(alignment: .leading, spacing: 4) {
            Text(SheetTabGridPresentation.cellReference(row: position.row, column: position.column))
                .font(Theme.font(.fieldLabel))
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("sheet-tab-cell-reference")
            Text(value)
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
