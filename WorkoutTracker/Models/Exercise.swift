import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var baseName: String
    var cadence: String?
    var coachNote: String?
    var order: Int
    var session: Session?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise) var sets: [ExerciseSet] = []

    init(name: String, baseName: String, cadence: String?, coachNote: String?, order: Int = 0) {
        self.name = name
        self.baseName = baseName
        self.cadence = cadence
        self.coachNote = coachNote
        self.order = order
    }
}

@Model
final class ExerciseSet {
    var index: Int
    var prescribedReps: String
    var prescribedLoad: String
    var percentOneRM: String?
    var stateRaw: String
    var setLogData: Data?
    var exercise: Exercise?

    var state: SetState {
        get { SetState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(index: Int, prescribedReps: String, prescribedLoad: String, percentOneRM: String?, state: SetState) {
        self.index = index
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.percentOneRM = percentOneRM
        self.stateRaw = state.rawValue
    }
}
