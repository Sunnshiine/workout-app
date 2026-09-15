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
}
