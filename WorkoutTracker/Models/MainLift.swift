import Foundation

/// One of the three barbell lifts the coach defines a Training Max for. The set is closed: the
/// Sheet's Training Max header area holds exactly these three labelled rows, and an Exercise
/// claims at most one of them.
///
/// Declaration order is load-bearing. It is the precedence `init(matchingBaseName:)` resolves an
/// ambiguous base name with, so "Squat Rack Bench Press" claims squat rather than bench.
enum MainLift: CaseIterable {
    case squat
    case bench
    case deadlift

    /// The whole-cell label the coach writes in the Training Max block's label column.
    private var sheetLabel: String {
        switch self {
        case .squat: "Squat"
        case .bench: "Bench Press"
        case .deadlift: "Deadlift"
        }
    }

    /// The lowercased fragment an Exercise's base name must contain to claim this lift's Training
    /// Max. Not the Sheet label lowercased: the Sheet says "Bench Press", but "Paused Bench Press"
    /// claims bench on "bench" alone.
    private var baseNameKeyword: String {
        switch self {
        case .squat: "squat"
        case .bench: "bench"
        case .deadlift: "deadlift"
        }
    }

    /// The lift a Training Max label cell names, matched case-insensitively against the whole
    /// trimmed cell. "Squat (comp)" and "OHP" name no lift.
    init?(sheetLabel cell: String) {
        guard
            let match = Self.allCases.first(where: {
                $0.sheetLabel.caseInsensitiveCompare(cell) == .orderedSame
            })
        else { return nil }
        self = match
    }

    /// The lift an Exercise's Cadence-stripped base name claims: lowercased substring, first match
    /// in declaration order. "Front Squat" claims squat; "RDL" claims nothing.
    ///
    /// Deliberately not `MovementMatching` (ADR-0013): that matcher draws different lines, and
    /// switching would silently change which Exercises get a Training Max.
    init?(matchingBaseName baseName: String) {
        let name = baseName.lowercased()
        guard let match = Self.allCases.first(where: { name.contains($0.baseNameKeyword) })
        else { return nil }
        self = match
    }
}
