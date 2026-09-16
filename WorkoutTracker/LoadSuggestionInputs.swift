import Foundation

/// The two Exercise-derived inputs `LoadSuggestionEngine.suggest` needs: the Training Max
/// that applies to this Exercise, and the weight the athlete last put on the bar.
extension Exercise {
    /// The Block Training Max that applies to this Exercise. Nothing when the base name claims no
    /// Main Lift, or when the Exercise sits outside a Block. `MainLift` owns the matching rule and
    /// the reasoning behind it.
    var trainingMax: Double? {
        guard let block = session?.week?.block, let lift = MainLift(matchingBaseName: baseName)
        else { return nil }
        return block.trainingMaxes[lift]
    }

    /// The nearest earlier Set's logged weight in pounds. Bodyweight and unlogged Sets carry no
    /// weight, so the scan passes over them to the next one back.
    func mostRecentLoggedPounds(before setIndex: Int) -> Double? {
        sets
            .filter { $0.index < setIndex }
            .sorted { $0.index > $1.index }
            .compactMap { previousSet -> Double? in
                switch previousSet.setLog?.weight {
                case .pounds(let pounds):
                    return pounds
                case .bodyweight, nil:
                    return nil
                }
            }
            .first
    }
}
