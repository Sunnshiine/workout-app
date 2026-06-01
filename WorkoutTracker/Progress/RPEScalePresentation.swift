import Foundation

/// One selectable value in the active set card's RPE chip scroller.
struct RPEChip: Equatable, Hashable, Identifiable, Sendable {
    let value: Double
    let label: String
    let isDimmed: Bool
    let isPrescribed: Bool
    let isSelected: Bool

    var id: Double { value }
    var accessibilityIdentifier: String { "rpe-\(label)" }
}

/// Drives the fixed-height horizontal RPE scroller that replaces the expanding
/// grid inside the active set card. The card never changes height, so the Log
/// button keeps a fixed Y — the scroller is the whole RPE control.
struct RPEScalePresentation: Equatable, Sendable {
    /// Where to center the scroller when neither a selection nor a prescription exists.
    static let defaultScrollTarget: Double = 8

    let chips: [RPEChip]
    let scrollTarget: Double

    init(prescribedRPE: Int?, selection: String) {
        let prescribedValue = prescribedRPE.map(Double.init)
        let selectedValue = Self.parse(selection)

        chips = Self.values.map { value in
            RPEChip(
                value: value,
                label: Self.label(value),
                isDimmed: value == Self.values.first,
                isPrescribed: value == prescribedValue,
                isSelected: value == selectedValue
            )
        }
        scrollTarget = selectedValue ?? prescribedValue ?? Self.defaultScrollTarget
    }

    private static let values: [Double] = [5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    private static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func label(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
