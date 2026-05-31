import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.resultText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("·")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(presentation.sourceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.lastPerformedCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(palette.lastPerformedCardStroke.opacity(0.85), lineWidth: 1)
        )
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
