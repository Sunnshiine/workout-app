import Foundation
import OSLog
import SwiftData

private let exerciseModelLogger = Logger(subsystem: "WorkoutTracker", category: "ExerciseModel")

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

    var setLog: SetLog? {
        get {
            guard let setLogData else { return nil }
            do {
                return try JSONDecoder().decode(SetLog.self, from: setLogData)
            } catch {
                exerciseModelLogger.error("Failed to decode SetLog: \(error.localizedDescription)")
                return nil
            }
        }
        set {
            guard let newValue else {
                setLogData = nil
                return
            }
            do {
                setLogData = try JSONEncoder().encode(newValue)
            } catch {
                exerciseModelLogger.error("Failed to encode SetLog: \(error.localizedDescription)")
            }
        }
    }

    var displayReps: String {
        if state == .logged, let setLog {
            return setLog.formatted
        }
        return prescribedReps
    }

    var displayLoad: String? {
        if state == .logged, setLog != nil {
            return nil
        }
        return prescribedLoad
    }

    init(index: Int, prescribedReps: String, prescribedLoad: String, percentOneRM: String?, state: SetState) {
        self.index = index
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.percentOneRM = percentOneRM
        self.stateRaw = state.rawValue
    }
}
