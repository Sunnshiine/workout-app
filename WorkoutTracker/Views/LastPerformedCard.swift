import SwiftUI

struct LastPerformedCard: View {
    let presentation: LastPerformedCardPresentation
    /// The Exercise History sheet's only entry point (revised `DESIGN.md` §Last Performed): when
    /// set, tapping the line opens the sheet. `nil` keeps the line a plain, non-tappable reference
    /// (e.g. inside a Superset side). Declared `let` — not a defaulted `var` — so every call site
    /// must state its intent, rather than silently omitting the tap (CODING_STANDARDS.md §optionals).
    let onTap: (() -> Void)?

    var body: some View {
        Group {
            if onTap != nil {
                line + disclosureHint
            } else {
                line
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint(onTap == nil ? "" : "Opens Exercise History")
        .modifier(TapModifier(onTap: onTap))
    }

    // Concatenated Text so multi-Set evidence wraps as one quiet paragraph
    // instead of truncating the trailing source label.
    private var line: Text {
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
    }

    // The subtlest disclosure hint — a low-emphasis chevron, no stroke or color shift, so it never
    // competes with the Active Set Card (revised `DESIGN.md` §Last Performed).
    private var disclosureHint: Text {
        Text("  ") + Text(Image(systemName: "chevron.forward"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
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
