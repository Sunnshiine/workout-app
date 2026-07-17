import Foundation

public enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    public static func suggest(
        prescribedLoad: String,
        percentOneRM: String?,
        previousSetWeight: Double?,
        trainingMax: Double?
    ) -> Double? {
        if let dropPercent = dropPercent(from: prescribedLoad), let previousSetWeight {
            let unrounded = previousSetWeight * (1 - dropPercent / 100)
            return roundToNearestPlateIncrement(unrounded)
        }

        if let percent = percentOneRMValue(from: percentOneRM), let trainingMax {
            let unrounded = trainingMax * percent / 100
            return roundToNearestPlateIncrement(unrounded)
        }

        return nil
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
