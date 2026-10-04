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
}

extension LoadSuggestionInputs {
    @MainActor
    init(set: ExerciseSet) {
        let exercise = set.exercise
        self.init(
            prescribedReps: set.prescribedReps,
            prescribedLoad: set.prescribedLoad,
            percentOneRM: set.percentOneRM,
            trainingMax: exercise?.trainingMax,
            earlierSets: (exercise?.sets ?? [])
                .filter { $0.index < set.index }
                .compactMap { earlier in earlier.setLog.map { (index: earlier.index, setLog: $0) } }
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
