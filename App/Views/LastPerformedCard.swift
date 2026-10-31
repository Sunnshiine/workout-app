import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation
    let onTap: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        Text("\(Image(systemName: "clock.arrow.circlepath")) \(line)")
            .themeFont(.lastPerformed)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(Theme.TypeRole.lastPerformed.denseFloorScale)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitOutset(HitOutset.textLine)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line)
            .accessibilityHint("Opens Exercise History")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("last-performed-line")
            .onTapGesture(perform: onTap)
            .givingBackHitOutset(HitOutset.textLine)
    }

    private var line: Text {
        Text("\(presentation.sourceText) — \(presentation.resultText)\(matchedNameText)")
    }

    // A tier-3 (Movement-level) line names the differently-spelled entry it matched (ADR-0013).
    private var matchedNameText: Text {
        guard let matchedName = presentation.matchedName else { return Text("") }
        return Text(" as “\(matchedName)”")
    }
}
