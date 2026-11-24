import Foundation

/// An earlier Set of the same Exercise that holds a Set Log, with the Load the coach prescribed for it.
struct EarlierSetLog: Sendable {
    let index: Int
    let setLog: SetLog
    let load: PrescribedLoad
}

struct LoadSuggestionInputs: Sendable {
    let prescription: Prescription
    let trainingMax: Double?
    /// Nearest first.
    let earlierSets: [EarlierSetLog]
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
            earlierSets: set.earlierSetLogs,
            lastPerformed: coordinates.flatMap {
                history.excluding(session: $0.session).lookup(for: $0.exercise.name)
            }
        )
    }
}

extension Exercise {
    var trainingMax: Double? {
        guard let block = session?.block, let lift = MainLift(claimedBy: exerciseName)
        else { return nil }
        return block.trainingMaxes[lift]
    }
}
