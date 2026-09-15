import CoreGraphics
import Foundation

/// One selectable value on a one-tap scroll rail (Reps or RPE) inside the Active
/// Set Card. The two rails share this shape and the `ValueRail` view; each
/// presentation below produces its own chips and the centered index (DESIGN.md §5.2).
struct ValueRailChip: Equatable, Hashable, Identifiable, Sendable {
    let label: String
    let isSelected: Bool
    let isPrescribed: Bool
    let accessibilityIdentifier: String

    var id: String { accessibilityIdentifier }
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

    /// The cell index a horizontal drag lands on: the strip follows the finger,
    /// so dragging left (negative translation) advances to higher values, one
    /// detent per cell stride from the index where the drag began.
    static func draggedIndex(
        anchorIndex: Int,
        translation: CGFloat,
        cellWidth: CGFloat,
        spacing: CGFloat,
        count: Int
    ) -> Int {
        let stride = cellWidth + spacing
        guard stride > 0, count > 0 else { return anchorIndex }
        let delta = Int((-translation / stride).rounded())
        return min(max(anchorIndex + delta, 0), count - 1)
    }
}

/// Drives the RPE one-tap scroll rail (5–10 in half steps). The card never
/// changes height, so the Log capsule keeps a fixed Y — the rail is the whole
/// RPE control.
struct RPEScalePresentation: Equatable, Sendable {
    private static let values: [Double] = [5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    private static let defaultCenter: Double = 8

    let chips: [ValueRailChip]
    let selectedIndex: Int

    init(prescribedRPE: Int?, selection: String) {
        let prescribed = prescribedRPE.map(Double.init)
        let selected = Double(selection.trimmingCharacters(in: .whitespacesAndNewlines))

        chips = Self.values.map { value in
            let label = value.rounded() == value ? String(Int(value)) : String(value)
            return ValueRailChip(
                label: label,
                isSelected: value == selected,
                isPrescribed: value == prescribed,
                accessibilityIdentifier: "rpe-\(label)"
            )
        }
        let center = selected ?? prescribed ?? Self.defaultCenter
        selectedIndex = Self.values.firstIndex(of: center) ?? Self.values.firstIndex(of: Self.defaultCenter) ?? 0
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
