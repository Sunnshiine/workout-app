import Foundation

/// Where a Set sits in the Sheet, in the semantic terms a pending write persists
/// (ADR-0006): Block tab, Week, Day, Exercise and its ordinal among same-named Exercises, Set
/// index — plus the Session date that the Last Performed index records alongside them.
struct SetCoordinates: Equatable {
    let session: SessionCoordinate
    let dayNumbering: DayNumbering
    let exerciseName: ExerciseName
    let exerciseOrdinal: Int
    let setIndex: Int
    let sessionDate: Date?

    @MainActor
    init(of set: ExerciseSet) throws {
        guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
        guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
        guard let coordinate = session.placement.coordinate, let block = session.block else {
            throw WorkoutLoggingError.detachedSession
        }
        self.session = coordinate
        self.dayNumbering = block.dayNumbering
        self.exerciseName = exercise.exerciseName
        self.exerciseOrdinal = exercise.ordinalAmongSameNamed(in: session)
        self.setIndex = set.index
        self.sessionDate = session.date
    }

    /// The part of a Set's coordinates that still names the same Set after a freshly parsed Block
    /// replaces the cached one, when both Blocks number their Days the same way. The Session date is
    /// re-read from the Sheet on every parse, so it can move while the Set stays the one a pending
    /// write addressed.
    struct ID: Hashable {
        let session: SessionCoordinate
        let exerciseName: ExerciseName
        let exerciseOrdinal: Int
        let setIndex: Int
    }
}

extension SetCoordinates.ID {
    @MainActor
    init(_ write: PendingWrite) {
        self.init(
            session: write.recordedSession,
            exerciseName: ExerciseName(entered: write.exerciseName),
            exerciseOrdinal: write.exerciseOrdinal,
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
                            session: SessionCoordinate(blockTab: tabName, address: week.address(of: session)),
                            exerciseName: exercise.exerciseName,
                            exerciseOrdinal: exercise.ordinalAmongSameNamed(in: session),
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

extension Exercise {
    /// How many Exercises earlier in `session` share this one's name: 0 for the first, 1 for a
    /// second Exercise the coach gave the same name. The Sheet layout counts its anchors the same
    /// way, so the pair (name, ordinal) addresses one row where the name alone matches several.
    @MainActor
    func ordinalAmongSameNamed(in session: Session) -> Int {
        session.exercises.count { $0.exerciseName == exerciseName && $0.order < order }
    }
}
