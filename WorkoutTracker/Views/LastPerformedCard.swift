import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation

    var body: some View {
        // Concatenated Text so multi-Set evidence wraps as one quiet paragraph
        // instead of truncating the trailing source label.
        (
            Text(presentation.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                + Text(" ")
                + Text(presentation.resultText)
                .font(.subheadline)
                .foregroundStyle(.primary)
                + Text(" · ")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                + Text(presentation.sourceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                + matchedNameText
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // A tier-3 (Movement-level) line names the differently-spelled entry it matched (ADR-0013).
    private var matchedNameText: Text {
        guard let matchedName = presentation.matchedName else { return Text("") }
        return Text(" as “\(matchedName)”")
            .font(.footnote)
            .italic()
            .foregroundStyle(.tertiary)
    }
}
