import Foundation

struct LoadSuggestionInputs: Sendable {
    let prescribedReps: String
    let prescribedLoad: String
    let percentOneRM: String?
    let trainingMax: Double?
    /// Nearest first.
    let earlierSets: [(index: Int, setLog: SetLog)]
    let lastPerformed: LastPerformedOccurrence?
}

extension LoadSuggestionInputs {
    @MainActor
    init(set: ExerciseSet, history: LastPerformedLookupSnapshot) {
        let exercise = set.exercise
        let coordinates = try? SetCoordinates(of: set)
        self.init(
            prescribedReps: set.prescribedReps,
            prescribedLoad: set.prescribedLoad,
            percentOneRM: set.percentOneRM,
            trainingMax: exercise?.trainingMax,
            earlierSets: (exercise?.sets ?? [])
                .filter { $0.index < set.index }
                .sorted { $0.index > $1.index }
                .compactMap { earlier in earlier.setLog.map { (index: earlier.index, setLog: $0) } },
            lastPerformed: coordinates.flatMap {
                history.excluding(session: $0.session).lookup(for: $0.exerciseName)?.occurrence
            }
        )
    }
}

extension Exercise {
    var trainingMax: Double? {
        guard let block = session?.week?.block, let lift = MainLift(matchingBaseName: baseName)
        else { return nil }
        return block.trainingMaxes[lift]
    }
}
