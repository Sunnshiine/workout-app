import SwiftUI

struct RPEGrid: View {
    let presentation: RPEGridPresentation
    @Binding var selection: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: Theme.rpeGridSpacing) {
            ForEach(presentation.rows.indices, id: \.self) { rowIndex in
                rowView(presentation.rows[rowIndex])
            }
        }
    }

    private func rowView(_ row: [RPEGridValue]) -> some View {
        HStack(spacing: Theme.rpeGridSpacing) {
            ForEach(row) { value in
                cellButton(for: value)
            }
        }
    }

    private func cellButton(for value: RPEGridValue) -> some View {
        Button {
            selection = String(value.value)
            Task {
                try? await Task.sleep(for: presentation.autoCloseDelay)
                isPresented = false
            }
        } label: {
            cellLabel(for: value)
        }
        .buttonStyle(.plain)
    }

    private func cellLabel(for value: RPEGridValue) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(String(value.value))
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: Theme.rpeGridCellHeight)
                .foregroundStyle(value.isDimmed ? Color.secondary : Color.white)

            if value.showsPrescriptionBadge {
                Text("Rx")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accentDarkText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.accent, in: .capsule)
                    .padding(6)
            }
        }
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(Theme.pillStroke, lineWidth: 1)
        )
        .opacity(value.isDimmed ? 0.55 : 1)
    }
}
