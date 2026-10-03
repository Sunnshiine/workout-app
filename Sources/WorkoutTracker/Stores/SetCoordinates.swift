import Foundation

/// Where a Set sits in the Sheet, in the semantic terms a pending write persists
/// (ADR-0006): Block tab, Week, Day, Exercise, Set index — plus the Session date and the
/// Exercise base name that the Last Performed index records alongside them.
struct SetCoordinates: Equatable {
    let session: SessionCoordinate
    let dayNumbering: DayNumbering
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
        self.session = SessionCoordinate(blockTab: block.tabName, address: week.address(of: session))
        self.dayNumbering = block.dayNumbering
        self.exerciseName = exercise.name
        self.exerciseBaseName = exercise.baseName
        self.setIndex = set.index
        self.sessionDate = session.date
    }

    /// The part of a Set's coordinates that still names the same Set after a freshly parsed Block
    /// replaces the cached one, when both Blocks number their Days the same way. The Session date
    /// and the Exercise base name are re-read from the Sheet on every parse, so they can move while
    /// the Set stays the one a pending write addressed.
    struct ID: Hashable {
        let session: SessionCoordinate
        let exerciseName: String
        let setIndex: Int
    }
}

extension SetCoordinates.ID {
    @MainActor
    init(_ write: PendingWrite) {
        self.init(session: write.recordedSession, exerciseName: write.exerciseName, setIndex: write.setIndex)
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
                            session: SessionCoordinate(blockTab: tabName, address: week.address(of: session)),
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
