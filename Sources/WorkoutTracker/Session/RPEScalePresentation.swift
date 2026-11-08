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

/// Drives the RPE one-tap scroll rail. The card never changes height, so the
/// Log capsule keeps a fixed Y — the rail is the whole RPE control.
struct RPEScalePresentation: Equatable, Sendable {
    private static let defaultCenter: RPE = .eight

    let chips: [ValueRailChip]
    let selectedIndex: Int

    init(prescribedRPE: RPE?, selection: String) {
        let selected = RPE(text: selection)

        chips = RPE.allCases.map { rpe in
            ValueRailChip(
                label: rpe.label,
                isSelected: rpe == selected,
                isPrescribed: rpe == prescribedRPE,
                accessibilityIdentifier: "rpe-\(rpe.label)"
            )
        }
        let center = selected ?? prescribedRPE ?? Self.defaultCenter
        selectedIndex = RPE.allCases.firstIndex(of: center) ?? 0
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

    /// Every value of a prescribed range carries the prescription tick, and the rail centers on
    /// its low end, the value the form pre-fills.
    init(prescribedReps: PrescribedReps, selection: String) {
        // Only the rail's own values: a range is Sheet text and can reach Int.max.
        let prescribed = prescribedReps.target.map { reps in Self.values.filter(reps.contains) } ?? []
        let selected = Int(selection.trimmingCharacters(in: .whitespacesAndNewlines))
        let centerValue = selected ?? prescribed.first ?? Self.defaultSelection

        chips = Self.values.map { value in
            ValueRailChip(
                label: String(value),
                isSelected: value == selected,
                isPrescribed: prescribed.contains(value),
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
