import Foundation

/// Where a Set sits in the Sheet, in the semantic terms a pending write persists
/// (ADR-0006): Block tab, Week, Day, Exercise Reference, Set index — plus the Session date that
/// the Last Performed index records alongside them.
struct SetCoordinates: Equatable {
    let session: SessionCoordinate
    let dayNumbering: DayNumbering
    let exercise: ExerciseReference
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
        self.exercise = exercise.reference(in: session)
        self.setIndex = set.index
        self.sessionDate = session.date
    }

    /// The part of a Set's coordinates that still names the same Set after a freshly parsed Block
    /// replaces the cached one, when both Blocks number their Days the same way. The Session date is
    /// re-read from the Sheet on every parse, so it can move while the Set stays the one a pending
    /// write addressed.
    struct ID: Hashable {
        let session: SessionCoordinate
        let exercise: ExerciseReference
        let setIndex: Int
    }

    /// The part of these coordinates a sync's re-parse keeps.
    var id: ID { ID(session: session, exercise: exercise, setIndex: setIndex) }
}

extension SetCoordinates.ID {
    @MainActor
    init(_ write: PendingWrite) {
        self.init(session: write.recordedSession, exercise: write.exercise, setIndex: write.setIndex)
    }
}

extension Block {
    /// A Set a sync took out of this Block can still read every link up to it, by the order
    /// SwiftData ran the cascade delete in (#1036), so this walks down from the Block instead.
    @MainActor
    func holds(_ set: ExerciseSet) -> Bool {
        let id = set.persistentModelID
        return weeks.lazy.flatMap(\.sessions).flatMap(\.exercises).flatMap(\.sets).contains { $0.persistentModelID == id }
    }

    /// Every Set in this Block, keyed by the coordinates the Sheet addresses it with. Walking down
    /// from the Block supplies the attachment `SetCoordinates(of:)` has to check for, so no Set
    /// reached this way can be detached.
    @MainActor
    var setsByID: [SetCoordinates.ID: ExerciseSet] {
        var sets: [SetCoordinates.ID: ExerciseSet] = [:]
        for week in weeks {
            for session in week.sessions {
                let coordinate = SessionCoordinate(blockTab: tabName, address: week.address(of: session))
                for exercise in session.exercises {
                    let reference = exercise.reference(in: session)
                    for set in exercise.sets {
                        sets[SetCoordinates.ID(session: coordinate, exercise: reference, setIndex: set.index)] = set
                    }
                }
            }
        }
        return sets
    }
}
