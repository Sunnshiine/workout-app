import SwiftUI
import UIKit

/// The Live Activity's rows of the app's type role table (`Theme.TypeRole`). The widget links no
/// library, so `themeFont(_:)` is out of its reach and these repeat its faces, sizes, and curves. The
/// compact and minimal island keep the system's face, since they sit in the status bar.
enum LiveActivityType {
    /// `queueName`: the Fraunces voice.
    case exerciseName
    /// `statsValue`.
    case largeFigure
    /// `railChipValue`: a load, reps, an RPE, and a countdown.
    case figure
    /// `logCapsule`.
    case control
    /// `runline`.
    case reference
    /// `lastPerformed`.
    case lastPerformed
    /// `lastPerformed` at the 12pt floor of DESIGN.md's Shrink-Then-Truncate Rule.
    case lastPerformedFloor
    /// `fieldLabel`.
    case label

    fileprivate var size: CGFloat {
        switch self {
        case .exerciseName: 20
        case .largeFigure: 28
        case .figure, .control: 17
        case .reference, .lastPerformed, .label: 13
        case .lastPerformedFloor: 12
        }
    }

    fileprivate var curve: UIFont.TextStyle {
        switch self {
        case .exerciseName: .title3
        case .largeFigure: .title1
        case .figure: .body
        case .control: .headline
        case .reference, .lastPerformed, .lastPerformedFloor: .footnote
        case .label: .caption1
        }
    }

    fileprivate func font(size: CGFloat) -> UIFont {
        let axes: [UInt32: Double]
        var attributes: [UIFontDescriptor.AttributeName: Any]
        switch self {
        case .exerciseName:
            axes = [Self.tag("wght"): weight, Self.tag("opsz"): Double(size), Self.tag("SOFT"): 100, Self.tag("WONK"): 0]
            attributes = [.family: "Fraunces"]
        case .largeFigure, .figure, .control, .reference, .lastPerformed, .lastPerformedFloor, .label:
            axes = [Self.tag("wght"): weight]
            attributes = [
                .family: "Source Sans 3",
                .featureSettings: [
                    [
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                    ]
                ]
            ]
        }
        attributes[UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)] = axes
        return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
    }

    private var weight: Double {
        switch self {
        case .exerciseName: 490
        case .largeFigure, .figure: 700
        case .lastPerformed, .lastPerformedFloor: 400
        case .control, .reference, .label: 600
        }
    }

    /// Source Sans 3 opens at caption sizes and tightens for display. Fraunces's optical size respaces it.
    fileprivate func tracking(at size: CGFloat) -> CGFloat {
        guard self != .exerciseName else { return 0 }
        switch size {
        case ..<13: return 0.01 * size
        case ..<28: return 0
        default: return -0.01 * size
        }
    }

    private static func tag(_ tag: String) -> UInt32 {
        tag.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}

extension View {
    /// Sets text in a Live Activity type role, scaled to the Dynamic Type size in the environment.
    func liveActivityFont(_ role: LiveActivityType) -> some View {
        modifier(LiveActivityTypeModifier(role: role))
    }
}

private struct LiveActivityTypeModifier: ViewModifier {
    let role: LiveActivityType
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let size = role.size * pointSize(at: dynamicTypeSize) / pointSize(at: .large)
        content
            .font(Font(role.font(size: size)))
            .tracking(role.tracking(at: size))
    }

    private func pointSize(at size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFont.preferredFont(forTextStyle: role.curve, compatibleWith: traits).pointSize
    }
}
