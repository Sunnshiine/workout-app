import Foundation

/// The two Exercise-derived inputs `LoadSuggestionEngine.suggest` needs: the Training Max
/// that applies to this Movement, and the weight the athlete last put on the bar.
extension Exercise {
    /// Which of the Block's three Training Maxes applies to this Exercise, by substring on the
    /// base name in squat/bench/deadlift order.
    ///
    /// Deliberately not `MovementMatching` (ADR-0013): that matcher draws different lines, and
    /// switching would silently change which Exercises get a Training Max.
    var trainingMax: Double? {
        guard let block = session?.week?.block else { return nil }
        let baseName = baseName.lowercased()
        if baseName.contains("squat") { return block.squatTM }
        if baseName.contains("bench") { return block.benchTM }
        if baseName.contains("deadlift") { return block.deadliftTM }
        return nil
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
