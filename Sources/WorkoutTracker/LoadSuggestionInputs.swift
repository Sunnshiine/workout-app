import Foundation

struct LoadSuggestionInputs: Sendable {
    let prescription: Prescription
    let trainingMax: Double?
    /// Nearest first.
    let earlierSets: [(index: Int, setLog: SetLog)]
    let lastPerformed: LastPerformedLookupEntry?
}

extension LoadSuggestionInputs {
    @MainActor
    init(set: ExerciseSet, history: LastPerformedLookupSnapshot) {
        let exercise = set.exercise
        let coordinates = try? SetCoordinates(of: set)
        self.init(
            prescription: set.prescription,
            trainingMax: exercise?.trainingMax,
            earlierSets: (exercise?.sets ?? [])
                .filter { $0.index < set.index }
                .sorted { $0.index > $1.index }
                .compactMap { earlier in earlier.setLog.map { (index: earlier.index, setLog: $0) } },
            lastPerformed: coordinates.flatMap {
                history.excluding(session: $0.session).lookup(for: $0.exerciseName)
            }
        )
    }
}

extension Exercise {
    var trainingMax: Double? {
        guard let block = session?.week?.block, let lift = MainLift(claimedBy: exerciseName)
        else { return nil }
        return block.trainingMaxes[lift]
    }
}
