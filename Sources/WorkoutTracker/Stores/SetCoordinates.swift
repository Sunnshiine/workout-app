import Foundation

/// Where a Set sits in the Sheet, in the semantic terms a pending write persists
/// (ADR-0006): Block tab, Week, Day, Exercise, Set index — plus the Session date and the
/// Exercise base name that the Last Performed index records alongside them.
struct SetCoordinates: Equatable {
    let blockTab: String
    let weekNumber: Int
    let dayNumber: Int
    let exerciseName: String
    let exerciseBaseName: String
    let setIndex: Int
    let sessionDate: Date?

    @MainActor
    init(of set: ExerciseSet) throws {
        guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
        guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
        guard let week = session.week else { throw WorkoutLoggingError.missingWeek }
        guard let block = week.block else { throw WorkoutLoggingError.missingBlock }
        self.blockTab = block.tabName
        self.weekNumber = week.number
        self.dayNumber = session.dayNumber
        self.exerciseName = exercise.name
        self.exerciseBaseName = exercise.baseName
        self.setIndex = set.index
        self.sessionDate = session.date
    }

    /// The part of a Set's coordinates that still names the same Set after a freshly parsed Block
    /// replaces the cached one. The Session date and the Exercise base name are re-read from the
    /// Sheet on every parse, so they can move while the Set stays the one a pending write addressed.
    struct ID: Hashable {
        let blockTab: String
        let weekNumber: Int
        let dayNumber: Int
        let exerciseName: String
        let setIndex: Int
    }
}

extension SetCoordinates.ID {
    @MainActor
    init(_ write: PendingWrite) {
        self.init(
            blockTab: write.blockTab,
            weekNumber: write.week,
            dayNumber: write.day,
            exerciseName: write.exerciseName,
            setIndex: write.setIndex
        )
    }
}

extension Block {
    /// Every Set in this Block, keyed by the coordinates the Sheet addresses it with. Walking down
    /// from the Block supplies the attachment `SetCoordinates(of:)` has to check for, so no Set
    /// reached this way can be detached.
    @MainActor
    var setsByID: [SetCoordinates.ID: ExerciseSet] {
        var sets: [SetCoordinates.ID: ExerciseSet] = [:]
        for week in weeks {
            for session in week.sessions {
                for exercise in session.exercises {
                    for set in exercise.sets {
                        let id = SetCoordinates.ID(
                            blockTab: tabName,
                            weekNumber: week.number,
                            dayNumber: session.dayNumber,
                            exerciseName: exercise.name,
                            setIndex: set.index
                        )
                        sets[id] = set
                    }
                }
            }
        }
        return sets
    }
}
