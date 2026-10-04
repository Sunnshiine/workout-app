import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func exercise(named baseName: String, inBlockWithTrainingMaxes: Bool = true) -> Exercise {
    let exercise = Exercise(name: baseName, baseName: baseName, cadence: nil, coachNote: nil)
    guard inBlockWithTrainingMaxes else { return exercise }
    let block = Block(tabName: "Block 27", trainingMaxes: [.squat: 405, .bench: 265, .deadlift: 500])
    let week = Week(number: 1)
    week.block = block
    let session = Session(dayNumber: 1, date: nil)
    session.week = week
    exercise.session = session
    return exercise
}

@MainActor
private func exercise(name: String, baseName: String, in block: Block) -> Exercise {
    let exercise = Exercise(name: name, baseName: baseName, cadence: nil, coachNote: nil)
    let week = Week(number: 1)
    week.block = block
    let session = Session(dayNumber: 1, date: nil)
    session.week = week
    exercise.session = session
    return exercise
}

@MainActor
@Suite struct TrainingMaxLookupTests {
    @Test func backSquatTakesTheSquatTrainingMax() {
        #expect(exercise(named: "Back Squat").trainingMax == 405)
    }

    @Test func pausedBenchPressTakesTheBenchTrainingMax() {
        #expect(exercise(named: "Paused Bench Press").trainingMax == 265)
    }

    @Test func deadliftTakesTheDeadliftTrainingMax() {
        #expect(exercise(named: "Deadlift").trainingMax == 500)
    }

    /// Open product question, not a change: substring matching means an accessory named
    /// "Front Squat" inherits the main lift's Training Max.
    @Test func frontSquatInheritsTheSquatTrainingMax() {
        #expect(exercise(named: "Front Squat").trainingMax == 405)
    }

    @Test func anExerciseMatchingNoMainLiftHasNoTrainingMax() {
        #expect(exercise(named: "RDL").trainingMax == nil)
    }

    @Test func anExerciseOutsideABlockHasNoTrainingMax() {
        #expect(exercise(named: "Back Squat", inBlockWithTrainingMaxes: false).trainingMax == nil)
    }

    @Test func matchingIgnoresCase() {
        #expect(exercise(named: "BACK SQUAT").trainingMax == 405)
        #expect(exercise(named: "back squat").trainingMax == 405)
    }

    /// Pinned end to end as well as on `MainLift`, because this is the order that decides which
    /// Training Max an athlete actually sees pre-filled.
    @Test func anAmbiguousBaseNameResolvesInSquatBenchDeadliftOrder() {
        #expect(exercise(named: "Squat Rack Bench Press").trainingMax == 405)
        #expect(exercise(named: "Bench Press from Deadlift Blocks").trainingMax == 265)
    }

    @Test func aBlankTrainingMaxOnThePresentBlockResolvesToNothing() {
        let block = Block(tabName: "Block 27", trainingMaxes: [.bench: 265, .deadlift: 500])

        #expect(exercise(name: "Back Squat", baseName: "Back Squat", in: block).trainingMax == nil)
    }

    @Test func matchingReadsTheBaseNameNotTheFullName() {
        let block = Block(tabName: "Block 27", trainingMaxes: [.squat: 405, .bench: 265, .deadlift: 500])

        #expect(exercise(name: "0:3:0 Back Squat", baseName: "Back Squat", in: block).trainingMax == 405)
        #expect(exercise(name: "Bench Press", baseName: "RDL", in: block).trainingMax == nil)
    }
}
