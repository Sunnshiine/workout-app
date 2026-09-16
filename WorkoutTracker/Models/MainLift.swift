import Foundation

/// One of the three lifts a Training Max is defined for. See CONTEXT.md, "Main Lift".
enum MainLift: CaseIterable {
    case squat
    case bench
    case deadlift

    /// The order an ambiguous base name resolves in, so "Squat Rack Bench Press" claims squat.
    private static let matchPrecedence: [MainLift] = [.squat, .bench, .deadlift]

    private var sheetLabel: String {
        switch self {
        case .squat: "Squat"
        case .bench: "Bench Press"
        case .deadlift: "Deadlift"
        }
    }

    /// Not the Sheet label lowercased. The Sheet says "Bench Press", but "Paused Bench Press"
    /// claims bench on "bench" alone, so deriving one spelling from the other would change which
    /// Exercises get a Training Max.
    private var baseNameKeyword: String {
        switch self {
        case .squat: "squat"
        case .bench: "bench"
        case .deadlift: "deadlift"
        }
    }

    init?(sheetLabel cell: String) {
        let cell = cell.trimmed
        guard
            let match = Self.allCases.first(where: {
                $0.sheetLabel.caseInsensitiveCompare(cell) == .orderedSame
            })
        else { return nil }
        self = match
    }

    /// Deliberately not `MovementMatching` (ADR-0013): that matcher draws different lines, and
    /// switching would silently change which Exercises get a Training Max.
    init?(matchingBaseName baseName: String) {
        let name = baseName.lowercased()
        guard let match = Self.matchPrecedence.first(where: { name.contains($0.baseNameKeyword) })
        else { return nil }
        self = match
    }
}
