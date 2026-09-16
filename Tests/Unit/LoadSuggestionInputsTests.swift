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
private func loggedSet(index: Int, weight: Weight?) -> ExerciseSet {
    let set = ExerciseSet(
        index: index,
        prescribedReps: "5",
        prescribedLoad: "RPE 8",
        percentOneRM: nil,
        state: weight == nil ? .pending : .logged
    )
    if let weight {
        set.setLog = SetLog(weight: weight, reps: 5, rpe: .eight)
    }
    return set
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

    /// Branch order is behaviour, not an accident. A base name carrying two keywords resolves to
    /// the earlier one, so these deliberately ambiguous names pin squat over bench over deadlift.
    @Test func anAmbiguousBaseNameResolvesInSquatBenchDeadliftOrder() {
        #expect(exercise(named: "Squat Rack Bench Press").trainingMax == 405)
        #expect(exercise(named: "Bench Press from Deadlift Blocks").trainingMax == 265)
    }

    /// The Block is there, but the coach left that lift's Training Max blank.
    @Test func aBlankTrainingMaxOnThePresentBlockResolvesToNothing() {
        let block = Block(tabName: "Block 27", trainingMaxes: [.bench: 265, .deadlift: 500])

        #expect(exercise(name: "Back Squat", baseName: "Back Squat", in: block).trainingMax == nil)
    }

    /// The rule reads the Cadence-stripped base name, never the full Exercise name, so a Cadence
    /// prefix cannot change the answer and a name-only keyword cannot manufacture one.
    @Test func matchingReadsTheBaseNameNotTheFullName() {
        let block = Block(tabName: "Block 27", trainingMaxes: [.squat: 405, .bench: 265, .deadlift: 500])

        #expect(exercise(name: "0:3:0 Back Squat", baseName: "Back Squat", in: block).trainingMax == 405)
        #expect(exercise(name: "Bench Press", baseName: "RDL", in: block).trainingMax == nil)
    }
}

@MainActor
@Suite struct MostRecentLoggedPoundsTests {
    @Test func takesTheNearestEarlierLoggedPounds() {
        let exercise = exercise(named: "Back Squat")
        exercise.sets = [
            loggedSet(index: 0, weight: .pounds(185)),
            loggedSet(index: 1, weight: .pounds(225)),
            loggedSet(index: 2, weight: nil)
        ]

        #expect(exercise.mostRecentLoggedPounds(before: 2) == 225)
    }

    @Test func skipsBodyweightAndUnloggedSets() {
        let exercise = exercise(named: "Back Squat")
        exercise.sets = [
            loggedSet(index: 0, weight: .pounds(185)),
            loggedSet(index: 1, weight: .bodyweight),
            loggedSet(index: 2, weight: nil)
        ]

        #expect(exercise.mostRecentLoggedPounds(before: 3) == 185)
    }

    @Test func theFirstSetHasNoEarlierWeight() {
        let exercise = exercise(named: "Back Squat")
        exercise.sets = [loggedSet(index: 0, weight: .pounds(185))]

        #expect(exercise.mostRecentLoggedPounds(before: 0) == nil)
    }
}
