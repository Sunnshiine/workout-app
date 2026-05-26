import Foundation

public enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    public static func suggest(
        prescribedLoad: String,
        previousSetWeight: Double?,
        trainingMax: Double?
    ) -> Double? {
        if let dropPercent = dropPercent(from: prescribedLoad), let previousSetWeight {
            let unrounded = previousSetWeight * (1 - dropPercent / 100)
            return roundToNearestPlateIncrement(unrounded)
        }

        if let percentOneRM = percentOneRM(from: prescribedLoad), let trainingMax {
            let unrounded = trainingMax * percentOneRM / 100
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

    private static func percentOneRM(from prescribedLoad: String) -> Double? {
        let trimmed = prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            trimmed.range(
                of: #"^[0-9]+(?:\.[0-9]+)?%1RM$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        else {
            return nil
        }

        let percentText = trimmed.dropLast(4)
        return Double(percentText)
    }

    private static func roundToNearestPlateIncrement(_ weight: Double) -> Double {
        (weight / plateIncrement).rounded() * plateIncrement
    }
}
