import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func makeSet() -> ExerciseSet {
    ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
}

@MainActor
private func makeExercise() -> Exercise {
    Exercise(name: "Back Squat - Comp", baseName: "Back Squat", cadence: nil, coachNote: nil)
}

@MainActor
@Suite struct SetCoordinatesTests {
    @Test func resolvesEveryFieldFromTheChain() throws {
        let block = Block(tabName: "Block 27")
        let week = Week(number: 3)
        week.block = block
        let session = Session(dayNumber: 4, date: Date(timeIntervalSinceReferenceDate: 100))
        session.week = week
        let exercise = makeExercise()
        exercise.session = session
        let set = makeSet()
        set.exercise = exercise

        let coordinates = try SetCoordinates(of: set)

        #expect(coordinates.blockTab == "Block 27")
        #expect(coordinates.weekNumber == 3)
        #expect(coordinates.dayNumber == 4)
        #expect(coordinates.exerciseName == "Back Squat - Comp")
        #expect(coordinates.exerciseBaseName == "Back Squat")
        #expect(coordinates.setIndex == 2)
        #expect(coordinates.sessionDate == Date(timeIntervalSinceReferenceDate: 100))
    }

    @Test func aSetWithNoExerciseIsMissingExercise() {
        let set = makeSet()

        #expect(throws: WorkoutLoggingError.missingExercise) { try SetCoordinates(of: set) }
    }

    @Test func anExerciseWithNoSessionIsMissingSession() {
        let set = makeSet()
        set.exercise = makeExercise()

        #expect(throws: WorkoutLoggingError.missingSession) { try SetCoordinates(of: set) }
    }

    @Test func aSessionWithNoWeekIsMissingWeek() {
        let exercise = makeExercise()
        exercise.session = Session(dayNumber: 1, date: nil)
        let set = makeSet()
        set.exercise = exercise

        #expect(throws: WorkoutLoggingError.missingWeek) { try SetCoordinates(of: set) }
    }

    @Test func aWeekWithNoBlockIsMissingBlock() {
        let session = Session(dayNumber: 1, date: nil)
        session.week = Week(number: 1)
        let exercise = makeExercise()
        exercise.session = session
        let set = makeSet()
        set.exercise = exercise

        #expect(throws: WorkoutLoggingError.missingBlock) { try SetCoordinates(of: set) }
    }

    @Test func aSessionWithNoDateHasNoSessionDate() throws {
        let week = Week(number: 1)
        week.block = Block(tabName: "Block 1")
        let session = Session(dayNumber: 1, date: nil)
        session.week = week
        let exercise = makeExercise()
        exercise.session = session
        let set = makeSet()
        set.exercise = exercise

        #expect(try SetCoordinates(of: set).sessionDate == nil)
    }
}
