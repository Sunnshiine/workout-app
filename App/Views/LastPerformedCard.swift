import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation
    let onTap: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .accessibilityHidden(true)
            line
                .lineLimit(1)
                .minimumScaleFactor(11.0 / 12.5)
                .truncationMode(.tail)
        }
        .font(Theme.font(.lastPerformed))
        .foregroundStyle(palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Exercise History")
        .accessibilityIdentifier("last-performed-line")
        .onTapGesture(perform: onTap)
    }

    private var line: Text {
        Text(presentation.sourceText)
            + Text(" — ")
            + Text(presentation.resultText)
            + matchedNameText
    }

    // A tier-3 (Movement-level) line names the differently-spelled entry it matched (ADR-0013).
    private var matchedNameText: Text {
        guard let matchedName = presentation.matchedName else { return Text("") }
        return Text(" as “\(matchedName)”")
            .italic()
    }
}
