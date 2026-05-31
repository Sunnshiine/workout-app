import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(presentation.label)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(presentation.resultText)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("·")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            Text(presentation.sourceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .layoutPriority(-1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
