import CoreGraphics
import Foundation

/// One selectable value on a one-tap scroll rail (Reps or RPE) inside the Active
/// Set Card. The two rails share this shape and the `ValueRail` view; each
/// presentation below produces its own chips and the centered index (DESIGN.md §5.2).
struct ValueRailChip: Equatable, Hashable, Identifiable, Sendable {
    let value: Double
    let label: String
    let isSelected: Bool
    let isPrescribed: Bool
    let accessibilityIdentifier: String

    var id: Double { value }
}

/// The deterministic offset that centers a rail's selected cell. The rails are
/// offset-driven, never `scrollTo`/`scrollPosition`: offscreen snapshot renders
/// never apply async scrolling (they leave the content offset at 0), so the
/// centered value is computed from layout instead (ledger salvage note 1).
enum ValueRailLayout {
    static func contentOffset(
        trackWidth: CGFloat,
        cellWidth: CGFloat,
        spacing: CGFloat,
        selectedIndex: Int
    ) -> CGFloat {
        let stride = cellWidth + spacing
        let selectedCenter = stride * CGFloat(selectedIndex) + cellWidth / 2
        return trackWidth / 2 - selectedCenter
    }
}

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

/// Drives the RPE one-tap scroll rail (5–10 in half steps). The card never
/// changes height, so the Log capsule keeps a fixed Y — the rail is the whole
/// RPE control.
struct RPEScalePresentation: Equatable, Sendable {
    /// Where to center the rail when neither a selection nor a prescription exists.
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

    /// The shared rail-chip shape the `ValueRail` view consumes (Reps and RPE render identically).
    var railChips: [ValueRailChip] {
        chips.map { chip in
            ValueRailChip(
                value: chip.value,
                label: chip.label,
                isSelected: chip.isSelected,
                isPrescribed: chip.isPrescribed,
                accessibilityIdentifier: chip.accessibilityIdentifier
            )
        }
    }

    /// The index the rail centers on (selection, else prescription, else 8).
    var selectedIndex: Int {
        Self.values.firstIndex(of: scrollTarget) ?? Self.values.firstIndex(of: Self.defaultScrollTarget) ?? 0
    }

    private static let values: [Double] = [5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    private static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func label(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// Drives the Reps one-tap scroll rail (1–100), matching RPE's cell recipe
/// (DESIGN.md §5.2). Reps was a tap-to-type pill in the pre-Greenhouse card;
/// the Greenhouse card reports reps on the same rail RPE uses.
struct RepsScalePresentation: Equatable, Sendable {
    /// The value the rail centers on when neither a selection nor a prescription resolves.
    static let defaultSelection = 5

    let chips: [ValueRailChip]
    let selectedIndex: Int

    init(prescribedReps: String, selection: String) {
        let prescribed = Int(prescribedReps.trimmingCharacters(in: .whitespacesAndNewlines))
        let selected = Int(selection.trimmingCharacters(in: .whitespacesAndNewlines))
        let centerValue = selected ?? prescribed ?? Self.defaultSelection

        chips = Self.values.map { value in
            ValueRailChip(
                value: Double(value),
                label: String(value),
                isSelected: value == selected,
                isPrescribed: value == prescribed,
                accessibilityIdentifier: "reps-\(value)"
            )
        }
        selectedIndex =
            Self.values.firstIndex(of: centerValue)
            ?? Self.values.firstIndex(of: Self.defaultSelection)
            ?? 0
    }

    private static let values: [Int] = Array(1...100)
}
