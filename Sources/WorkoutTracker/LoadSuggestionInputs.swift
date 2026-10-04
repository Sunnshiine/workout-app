import Foundation

/// Every value a Load Suggestion reads, gathered once, so `LoadSuggestionEngine.suggest(_:)` and its
/// tests never touch SwiftData.
struct LoadSuggestionInputs: Sendable {
    let prescribedReps: String
    let prescribedLoad: String
    let percentOneRM: String?
    let trainingMax: Double?
    /// The Exercise's logged Sets before this one, in any order.
    let earlierSets: [(index: Int, setLog: SetLog)]
    /// The Exercise's most recent Exercise History entry outside this Set's own Session.
    let lastPerformed: LastPerformedOccurrence?
}

extension LoadSuggestionInputs {
    @MainActor
    init(set: ExerciseSet, history: LastPerformedLookupSnapshot) {
        let exercise = set.exercise
        // A Set outside a Block names no Session to leave out, so it reads no history.
        let coordinates = try? SetCoordinates(of: set)
        self.init(
            prescribedReps: set.prescribedReps,
            prescribedLoad: set.prescribedLoad,
            percentOneRM: set.percentOneRM,
            trainingMax: exercise?.trainingMax,
            earlierSets: (exercise?.sets ?? [])
                .filter { $0.index < set.index }
                .compactMap { earlier in earlier.setLog.map { (index: earlier.index, setLog: $0) } },
            lastPerformed: coordinates.flatMap {
                history.excluding(session: $0.session).lookup(for: $0.exerciseName)?.occurrence
            }
        )
    }
}

extension Exercise {
    /// The Training Max that applies to this Exercise. `MainLift` owns the matching rule and the
    /// reasoning behind it.
    var trainingMax: Double? {
        guard let block = session?.week?.block, let lift = MainLift(matchingBaseName: baseName)
        else { return nil }
        return block.trainingMaxes[lift]
    }
}
