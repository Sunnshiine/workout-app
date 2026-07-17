import Foundation

/// The outcome of a Load Suggestion: a calculated weight hint, the bodyweight
/// pre-fill when the coach prescribes `BW`, or no suggestion at all.
public enum LoadSuggestion: Equatable, Sendable {
    case weight(Double)
    case bodyweight
    case none
}

public enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    /// Owns the full Drop → %1RM → BW → none source selection. BW takes
    /// precedence over Drop and %1RM: a bodyweight-prescribed Set pre-fills BW
    /// even when a `percentOneRM` value is also present.
    public static func suggest(
        prescribedLoad: String,
        percentOneRM: String?,
        previousSetWeight: Double?,
        trainingMax: Double?
    ) -> LoadSuggestion {
        if isBodyweight(prescribedLoad) {
            return .bodyweight
        }

        if let dropPercent = dropPercent(from: prescribedLoad), let previousSetWeight {
            let unrounded = previousSetWeight * (1 - dropPercent / 100)
            return .weight(roundToNearestPlateIncrement(unrounded))
        }

        if let percent = percentOneRMValue(from: percentOneRM), let trainingMax {
            let unrounded = trainingMax * percent / 100
            return .weight(roundToNearestPlateIncrement(unrounded))
        }

        return .none
    }

    private static func isBodyweight(_ prescribedLoad: String) -> Bool {
        prescribedLoad
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("BW") == .orderedSame
    }

    private static func dropPercent(from prescribedLoad: String) -> Double? {
        let trimmed = prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            trimmed.range(
                of: #"^Drop\s+([0-9]+(?:\.[0-9]+)?)%$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        else {
            return nil
        }

        let percentText =
            trimmed
            .replacing(/^Drop\s+/.ignoresCase(), with: "")
            .replacing("%", with: "")
        return Double(percentText)
    }

    /// The `%1RM` prescription is stored structured as a `%`-suffixed string
    /// (e.g. `"75%"`, `ExerciseSet.percentOneRM`); parse it to a number once here.
    private static func percentOneRMValue(from percentOneRM: String?) -> Double? {
        guard let percentOneRM else { return nil }
        let trimmed = percentOneRM.trimmingCharacters(in: .whitespacesAndNewlines)
        let numberText = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        return Double(numberText)
    }

    private static func roundToNearestPlateIncrement(_ weight: Double) -> Double {
        (weight / plateIncrement).rounded() * plateIncrement
    }
}
