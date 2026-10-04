import Foundation

/// The outcome of a Load Suggestion: the coach's arithmetic (a Drop or a %1RM), the bodyweight
/// pre-fill when the coach prescribes `BW`, or no suggestion at all.
enum LoadSuggestion: Equatable, Sendable {
    case weight(Double)
    case bodyweight
    case noSuggestion
}

enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    /// CONTEXT.md *Load Suggestion*, the coach's explicit numbers first. The first arm that answers
    /// wins, so `BW` pre-fills BW even when a `percentOneRM` value is also present.
    private static let precedence: [@Sendable (LoadSuggestionInputs) -> LoadSuggestion?] = [
        bodyweight, drop, percentOneRM
    ]

    /// The question the Set card asks. A Set that holds a structured Set Log shows that log, so it
    /// consults nothing.
    @MainActor
    static func suggest(for set: ExerciseSet) -> LoadSuggestion {
        guard set.setLog == nil else { return .noSuggestion }
        return suggest(LoadSuggestionInputs(set: set))
    }

    static func suggest(_ inputs: LoadSuggestionInputs) -> LoadSuggestion {
        precedence.lazy.compactMap { $0(inputs) }.first ?? .noSuggestion
    }

    private static func bodyweight(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        Weight(text: inputs.prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)) == .bodyweight
            ? .bodyweight : nil
    }

    private static func drop(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard let dropPercent = dropPercent(from: inputs.prescribedLoad), let previous = previousSetPounds(inputs)
        else { return nil }
        return .weight(roundToNearestPlateIncrement(previous * (1 - dropPercent / 100)))
    }

    private static func percentOneRM(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard let percent = percentOneRMValue(from: inputs.percentOneRM), let trainingMax = inputs.trainingMax
        else { return nil }
        return .weight(roundToNearestPlateIncrement(trainingMax * percent / 100))
    }

    /// The nearest earlier Set's logged weight in pounds. A bodyweight Set carries no weight, so the
    /// scan passes over it to the next one back.
    private static func previousSetPounds(_ inputs: LoadSuggestionInputs) -> Double? {
        inputs.earlierSets
            .sorted { $0.index > $1.index }
            .lazy
            .compactMap { earlier -> Double? in
                guard case .pounds(let pounds) = earlier.setLog.weight else { return nil }
                return pounds
            }
            .first
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
