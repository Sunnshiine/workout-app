import SwiftUI

#if canImport(UIKit)
    import CoreText
    import UIKit
#endif

// MARK: - Type roles (token sheet §4)
//
// Every text style is one row of this role table, and a view reaches it only through
// `themeFont(_:)`, which sets the face, size, tracking and leading together and scales them with
// Dynamic Type (DESIGN.md §3). Fraunces is the voice, pinned at SOFT 100 / WONK 0 / wght 490 with
// opsz tracking the point size; Source Sans 3 is the instrument, its figures always tabular.

extension Theme {
    enum FontFace {
        case fraunces
        case sourceSans3

        /// The bundled variable font's family name (verified from the TTF `name` tables).
        var familyName: String {
            switch self {
            case .fraunces: "Fraunces"
            case .sourceSans3: "Source Sans 3"
            }
        }
    }

    /// One row of the type role table: a face at its default point size, a variable-font weight
    /// axis value, and the leading of a role that wraps.
    struct TypeStyle: Equatable {
        let face: FontFace
        let size: CGFloat
        /// Variable-font `wght` axis value. Fraunces ignores this (pinned at 490).
        let weight: Double
        /// Line height as a multiple of the point size; `nil` on roles that never wrap.
        let lineHeight: CGFloat?
        /// `opsz` axis override for the rare role where optical size ≠ point size.
        let opticalSize: CGFloat?

        init(face: FontFace, size: CGFloat, weight: Double, lineHeight: CGFloat? = nil, opticalSize: CGFloat? = nil) {
            self.face = face
            self.size = size
            self.weight = weight
            self.lineHeight = lineHeight
            self.opticalSize = opticalSize
        }

        /// Letter-spacing in points at a rendered size, set by that size (DESIGN.md §3 The Tracking
        /// Follows Size Rule), so a caption scaled up by Dynamic Type stops opening. Fraunces takes
        /// none: its opsz axis already respaces the face for each size.
        func tracking(at pointSize: CGFloat) -> CGFloat {
            guard face == .sourceSans3 else { return 0 }
            let em: CGFloat =
                switch pointSize {
                case ..<13: 0.01
                case ..<28: 0
                case ..<46: -0.01
                default: -0.015
                }
            return em * pointSize
        }
    }

    /// The smallest a reference line shrinks to before it truncates (DESIGN.md §3 The
    /// Shrink-Then-Truncate Rule).
    static let denseFloor: CGFloat = 12

    enum TypeRole: CaseIterable {
        case exerciseName
        case ceremonyTitle
        case connectTitle
        case sheetTitle
        case heading
        case supersetPartner
        case weightEntry
        case countdownNumeral
        case logCapsule
        case setNumber
        case setOf
        case railChipValue
        case railChipGlyph
        case fieldLabel
        case coachNote
        case runline
        case runlineSecondary
        case lastPerformed
        case queuePill
        case historyChip
        case blockTitle
        case cadence
        case statsValue
        case statsKey
        case sheetCell

        /// One row per role, in declaration order. A table has no compiler exhaustiveness check,
        /// so `everyTypeRoleHasAStyle` in `Tests/Component/ThemeTypeRoleTests.swift` is what keeps
        /// a new role from reaching `style` without a row. Source Sans 3 sizes come from the scale
        /// 12 · 13 · 15 · 17 · 28 · 46 · 96, and its weights from 400 · 600 · 700.
        private static let styles: [TypeRole: TypeStyle] = [
            .exerciseName: TypeStyle(face: .fraunces, size: 33, weight: 490, lineHeight: 1.1),
            .ceremonyTitle: TypeStyle(face: .fraunces, size: 36, weight: 490, lineHeight: 1.1),
            .connectTitle: TypeStyle(face: .fraunces, size: 36, weight: 490, lineHeight: 1.1),
            .sheetTitle: TypeStyle(face: .fraunces, size: 24, weight: 490, lineHeight: 1.1, opticalSize: 22),
            .heading: TypeStyle(face: .sourceSans3, size: 17, weight: 600),
            // The Superset "& partner" name line: the warm serif voice, subordinate to the
            // 33pt focused Exercise name and doubling as the manual focus switch (DESIGN.md §5.4).
            .supersetPartner: TypeStyle(face: .fraunces, size: 20, weight: 490),
            .weightEntry: TypeStyle(face: .sourceSans3, size: 46, weight: 700),
            // An Effort Countdown's seconds, read at arm's length from the machine's seat (#1157).
            .countdownNumeral: TypeStyle(face: .sourceSans3, size: 96, weight: 700),
            .logCapsule: TypeStyle(face: .sourceSans3, size: 17, weight: 600),
            .setNumber: TypeStyle(face: .sourceSans3, size: 17, weight: 700),
            .setOf: TypeStyle(face: .sourceSans3, size: 15, weight: 400),
            .railChipValue: TypeStyle(face: .sourceSans3, size: 17, weight: 700),
            .railChipGlyph: TypeStyle(face: .sourceSans3, size: 13, weight: 400),
            .fieldLabel: TypeStyle(face: .sourceSans3, size: 12, weight: 600),
            .coachNote: TypeStyle(face: .sourceSans3, size: 15, weight: 400, lineHeight: 1.5),
            .runline: TypeStyle(face: .sourceSans3, size: 13, weight: 600),
            .runlineSecondary: TypeStyle(face: .sourceSans3, size: 13, weight: 400),
            .lastPerformed: TypeStyle(face: .sourceSans3, size: 13, weight: 400),
            .queuePill: TypeStyle(face: .sourceSans3, size: 13, weight: 600),
            .historyChip: TypeStyle(face: .sourceSans3, size: 12, weight: 600),
            .blockTitle: TypeStyle(face: .sourceSans3, size: 28, weight: 700),
            .cadence: TypeStyle(face: .sourceSans3, size: 12, weight: 600),
            .statsValue: TypeStyle(face: .sourceSans3, size: 28, weight: 700),
            .statsKey: TypeStyle(face: .sourceSans3, size: 12, weight: 600),
            .sheetCell: TypeStyle(face: .sourceSans3, size: 12, weight: 400)
        ]

        var style: TypeStyle {
            guard let style = Self.styles[self] else { preconditionFailure("No TypeStyle for \(self)") }
            return style
        }

        /// The `minimumScaleFactor` that stops this role's shrink at the dense floor.
        var denseFloorScale: CGFloat {
            min(1, Theme.denseFloor / style.size)
        }
    }

    /// The single choke point through which a role resolves to a `Font` at a Dynamic Type size.
    /// Views reach it through `themeFont(_:)`.
    static func font(_ role: TypeRole, at dynamicTypeSize: DynamicTypeSize) -> Font {
        font(role.style, size: pointSize(role, at: dynamicTypeSize))
    }

    /// The role's point size at a Dynamic Type size, on its curve in `TypeScale`.
    static func pointSize(_ role: TypeRole, at dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
            return scaledSize(role, at: dynamicTypeSize)
        #else
            return role.style.size
        #endif
    }

    static func font(_ style: TypeStyle, size: CGFloat) -> Font {
        #if canImport(UIKit)
            return Font(uiFont(style, size: size))
        #else
            // Fonts aren't registered off-device (unit tests on macOS); fall back to a fixed-size
            // face so type still resolves without SwiftUI's own Dynamic Type scaling (the #410 trap).
            return Font.custom(style.face.familyName, fixedSize: size).weight(swiftUIWeight(style.weight))
        #endif
    }

    static func swiftUIWeight(_ axis: Double) -> Font.Weight {
        switch axis {
        case ..<250: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }

    #if canImport(UIKit)
        /// Builds the concrete `UIFont` for a role at a point size, driving the variable-font axes
        /// directly (SwiftUI's `.bold()` does not) and requesting tabular figures from Source Sans 3.
        static func uiFont(_ style: TypeStyle, size: CGFloat) -> UIFont {
            var axes: [UInt32: Double] = [:]
            var attributes: [UIFontDescriptor.AttributeName: Any] = [.family: style.face.familyName]
            switch style.face {
            case .fraunces:
                axes[fontTag("wght")] = 490
                axes[fontTag("opsz")] = Double((style.opticalSize ?? style.size) * size / style.size)
                axes[fontTag("SOFT")] = 100
                axes[fontTag("WONK")] = 0
            case .sourceSans3:
                axes[fontTag("wght")] = style.weight
                attributes[.featureSettings] = [
                    [
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                    ]
                ]
            }
            attributes[UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)] = axes
            return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
        }

        /// The OpenType axis/feature tag as its big-endian `FourCharCode`.
        private static func fontTag(_ tag: String) -> UInt32 {
            tag.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
        }
    #endif
}

extension View {
    /// Sets text in a type role: its face, size, tracking and leading, scaled to the Dynamic Type
    /// size in the environment.
    func themeFont(_ role: Theme.TypeRole) -> some View {
        modifier(ThemeTypeModifier(role: role))
    }
}

extension Text {
    /// Sets a run of a concatenated `Text` in a type role, which a view modifier cannot reach. It
    /// carries the role's face and tracking; leading belongs to the whole paragraph.
    func themeFont(_ role: Theme.TypeRole, at dynamicTypeSize: DynamicTypeSize) -> Text {
        let style = role.style
        let size = Theme.pointSize(role, at: dynamicTypeSize)
        return font(Theme.font(style, size: size)).tracking(style.tracking(at: size))
    }
}

private struct ThemeTypeModifier: ViewModifier {
    let role: Theme.TypeRole
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let style = role.style
        let size = Theme.pointSize(role, at: dynamicTypeSize)
        let leading = style.lineHeight.map { $0 * size }
        content
            .font(Theme.font(style, size: size))
            .tracking(style.tracking(at: size))
            .modifier(ExactLeading(points: leading))
    }
}

private struct ExactLeading: ViewModifier {
    let points: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.lineHeight(points.map { .exact(points: $0) })
        } else {
            content
        }
    }
}
