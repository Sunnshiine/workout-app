import SwiftUI
import UIKit

/// The Live Activity's rows of the app's type role table (`Theme.TypeRole`). The widget links no
/// library, so `themeFont(_:)` is out of its reach and these repeat its faces, sizes, and curves. The
/// compact and minimal island keep the system's face, since they sit in the status bar.
enum LiveActivityType {
    /// `queueName`: the Fraunces voice.
    case exerciseName
    /// `weightEntry`, set solid: the Lock Screen card's countdown, with the Cadence right under it.
    case countdown
    /// `statsValue`.
    case largeFigure
    /// `statsValue` on the leading the Lock Screen card stacks under a caption.
    case statValue
    /// `railChipValue`: a load, reps, an RPE, and a countdown.
    case figure
    /// `logCapsule`.
    case control
    /// `runline`.
    case reference
    /// `lastPerformed`'s face, which the Lock Screen card's line of Cadence and Coach Note takes.
    case guidance
    /// `fieldLabel`.
    case label
    /// `coachNote`.
    case coachNote
    /// `queuePill`.
    case pill
    /// `historyChip`'s face, which the Lock Screen card's stat labels and its Cadence take.
    case caption

    fileprivate var size: CGFloat {
        switch self {
        case .countdown: 46
        case .largeFigure, .statValue: 28
        case .exerciseName: 20
        case .figure, .control: 17
        case .coachNote, .pill: 15
        case .reference, .guidance, .label: 13
        case .caption: 12
        }
    }

    /// How a role sets its lines, in multiples of the type size.
    enum Leading: Equatable {
        /// The face's own line height.
        case face
        /// One line, centred in a box this high. The system sets an exact line height from the ascent
        /// down, so the line moves up by half of what the box cut off (measured 2026-11-10).
        case line(CGFloat)
        /// Lines that wrap, this far apart. The system's render of a Live Activity cuts a wrapped
        /// Text set at an exact line height with no "…", and one line of it keeps its "…" (measured
        /// 2026-11-10), so this leading goes between the lines.
        case wrapped(CGFloat)
    }

    var leading: Leading {
        switch self {
        case .countdown: .line(1)
        case .statValue: .line(1.15)
        case .caption: .line(1.3)
        case .coachNote: .wrapped(1.5)
        case .exerciseName, .largeFigure, .figure, .control, .reference, .guidance, .label, .pill: .face
        }
    }

    fileprivate var curve: UIFont.TextStyle {
        switch self {
        case .countdown: .largeTitle
        case .exerciseName: .title3
        case .largeFigure, .statValue: .title1
        case .figure: .body
        case .control: .headline
        case .coachNote: .subheadline
        case .reference, .guidance, .pill: .footnote
        case .label, .caption: .caption1
        }
    }

    fileprivate func font(size: CGFloat) -> UIFont {
        let axes: [UInt32: Double]
        var attributes: [UIFontDescriptor.AttributeName: Any]
        switch self {
        case .exerciseName:
            axes = [Self.tag("wght"): weight, Self.tag("opsz"): Double(size), Self.tag("SOFT"): 100, Self.tag("WONK"): 0]
            attributes = [.family: "Fraunces"]
        case .countdown, .largeFigure, .statValue, .figure, .control, .reference, .guidance, .label, .coachNote, .pill, .caption:
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
        case .countdown, .largeFigure, .statValue, .figure: 700
        case .guidance, .coachNote: 400
        case .control, .reference, .label, .pill, .caption: 600
        }
    }

    /// Source Sans 3 opens at caption sizes and tightens for display. Fraunces's optical size respaces it.
    fileprivate func tracking(at size: CGFloat) -> CGFloat {
        guard self != .exerciseName else { return 0 }
        switch size {
        case ..<13: return 0.01 * size
        case ..<28: return 0
        case ..<46: return -0.01 * size
        default: return -0.015 * size
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
        let font = role.font(size: size)
        let set = content.font(Font(font)).tracking(role.tracking(at: size))
        switch role.leading {
        case .face: set
        case .line(let height):
            set.lineHeight(.exact(points: height * size)).lineLimit(1).offset(y: (height * size - font.lineHeight) / 2)
        case .wrapped(let height): set.lineSpacing(height * size - font.lineHeight)
        }
    }

    private func pointSize(at size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFont.preferredFont(forTextStyle: role.curve, compatibleWith: traits).pointSize
    }
}
