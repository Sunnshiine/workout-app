import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

extension Theme {
    /// How each role grows with Dynamic Type: the system text style whose curve scales the role's
    /// own size, so a role at `.large` keeps its row's size exactly.
    enum TypeScale {
        /// The largest size app-drawn text renders at, on every screen. Past it the stage's
        /// fixed-size controls fall back to the Large Content Viewer. At `.accessibility1` the card
        /// grew 64pt and the two-Exercise `session` fixture shed its coach note and Last Performed,
        /// the History sheet's only entry point, on an iPhone 17 Pro; at this size it keeps every
        /// row, a rail cell still holds "100", and the sheets keep their proportions (operator,
        /// 2026-10-31: the uncapped sheets at AX5 looked "horribly large").
        static let largestSize: DynamicTypeSize = .xxxLarge

        /// One curve per role. `everyTypeRoleHasACurve` in `Tests/Component/ThemeTypeRoleTests.swift`
        /// keeps a new role from reaching `curve` without a row.
        private static let curves: [TypeRole: Font.TextStyle] = [
            .exerciseName: .largeTitle,
            .ceremonyTitle: .largeTitle,
            .connectTitle: .largeTitle,
            .weightEntry: .largeTitle,
            .blockTitle: .title,
            .statsValue: .title,
            .sheetTitle: .title2,
            .supersetPartner: .title3,
            .heading: .headline,
            .logCapsule: .headline,
            .railChipValue: .body,
            .setNumber: .callout,
            .setOf: .subheadline,
            .coachNote: .subheadline,
            .railChipGlyph: .footnote,
            .runline: .footnote,
            .runlineSecondary: .footnote,
            .lastPerformed: .footnote,
            .queuePill: .footnote,
            .statsKey: .footnote,
            .fieldLabel: .caption,
            .historyChip: .caption,
            .sheetCell: .caption,
            .cadence: .caption2
        ]

        static func curve(_ role: TypeRole) -> Font.TextStyle {
            guard let curve = curves[role] else { preconditionFailure("No Dynamic Type curve for \(role)") }
            return curve
        }
    }

    #if canImport(UIKit)
        /// The role's size times its curve's growth from `.large`, up to `TypeScale.largestSize`.
        /// `UIFontMetrics.scaledValue` would round to the pixel grid and move a 13.5pt role to 13.67
        /// at the default size.
        static func scaledSize(_ role: TypeRole, at size: DynamicTypeSize) -> CGFloat {
            let size = min(size, TypeScale.largestSize)
            let style = uiTextStyle(TypeScale.curve(role))
            return role.style.size * pointSize(of: style, at: size) / pointSize(of: style, at: .large)
        }

        private static func pointSize(of style: UIFont.TextStyle, at size: DynamicTypeSize) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
        }

        private static let uiTextStyles: [Font.TextStyle: UIFont.TextStyle] = [
            .largeTitle: .largeTitle, .title: .title1, .title2: .title2, .title3: .title3,
            .headline: .headline, .body: .body, .callout: .callout, .subheadline: .subheadline,
            .footnote: .footnote, .caption: .caption1, .caption2: .caption2
        ]

        private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
            uiTextStyles[style] ?? .body
        }
    #endif
}

extension View {
    /// Sets a type role at the environment's Dynamic Type size. A surface caps its growth with
    /// `.dynamicTypeSize(...)`, which this reads.
    func themeFont(_ role: Theme.TypeRole) -> some View {
        modifier(ThemeFontModifier(role: role))
    }
}

private struct ThemeFontModifier: ViewModifier {
    let role: Theme.TypeRole
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(Theme.font(role, at: dynamicTypeSize))
    }
}
