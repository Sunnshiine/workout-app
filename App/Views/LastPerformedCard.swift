import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation
    /// The Exercise History sheet's only entry point (`DESIGN.md` §5.1): when
    /// set, tapping the line opens the sheet. `nil` keeps the line a plain, non-tappable reference
    /// (e.g. inside a Superset side). Declared `let` — not a defaulted `var` — so every call site
    /// must state its intent, rather than silently omitting the tap (CODING_STANDARDS.md §optionals).
    let onTap: (() -> Void)?

    @Environment(\.themePalette) private var palette

    var body: some View {
        line
            .font(Theme.font(.lastPerformed))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(11.0 / 12.5)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityHint(onTap == nil ? "" : "Opens Exercise History")
            .modifier(TapModifier(onTap: onTap))
    }

    // `W1 D2 — 90×5 @8 · 90×5 @8 · …`: the source anchors the line, an em dash
    // leads into the Set-Log evidence.
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
            .foregroundStyle(.tertiary)
    }
}

private struct TapModifier: ViewModifier {
    let onTap: (() -> Void)?

    func body(content: Content) -> some View {
        if let onTap {
            content.onTapGesture(perform: onTap)
        } else {
            content
        }
    }
}
