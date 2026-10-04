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

private func benchEntry(_ resultText: String, at source: String, performedOn: Double) -> LastPerformedOccurrence {
    LastPerformedOccurrence(
        fullName: "Bench Press",
        baseName: "Bench Press",
        resultText: resultText,
        performedOn: Date(timeIntervalSinceReferenceDate: performedOn),
        source: source
    )
}

private let historyWithTheSetsOwnSession = LastPerformedLookupSnapshot(occurrences: [
    benchEntry("185x5@7, 195x5@8", at: "Block 26 · W4 D1", performedOn: 90),
    benchEntry("405x5@7", at: "Block 27 · W1 D2", performedOn: 200)
])

@MainActor
@Suite struct SuggestForASetTests {
    @Test func theBasisLeavesOutTheSetsOwnSession() throws {
        let set = makeBenchPress(loads: ["RPE6", "RPE7"]).sets.sorted { $0.index < $1.index }[0]
        let basis = try #require(
            LoadBasis(
                setLog: SetLog(weight: .pounds(195), reps: 5, rpe: .eight),
                origin: .history(SessionCoordinate(blockTab: "Block 26", address: SessionAddress(week: 4, day: 1)), matchedName: nil)
            )
        )

        #expect(LoadSuggestionEngine.suggest(for: set, history: historyWithTheSetsOwnSession) == .estimate(182.5, basis: basis))
    }

    @Test func theSetsPercentOneRMOfItsExercisesTrainingMaxBeatsHistory() {
        let set = makeBenchPress(loads: ["RPE6"], trainingMaxes: [.bench: 265]).sets[0]
        set.percentOneRM = "70%"

        #expect(LoadSuggestionEngine.suggest(for: set, history: historyWithTheSetsOwnSession) == .prescribedWeight(185))
    }

    @Test func anEarlierLoggedSetOfTheExerciseIsTheBasis() throws {
        let sets = makeBenchPress(loads: ["RPE6", "RPE7"]).sets.sorted { $0.index < $1.index }
        let setOne = SetLog(weight: .pounds(185), reps: 5, rpe: .seven)
        sets[0].markLogged(setOne, at: Date(timeIntervalSinceReferenceDate: 0))
        let basis = try #require(LoadBasis(setLog: setOne, origin: .today(setIndex: 0)))

        #expect(LoadSuggestionEngine.suggest(for: sets[1], history: historyWithTheSetsOwnSession) == .estimate(185, basis: basis))
    }

    @Test func dropReadsTheNearestEarlierSetOfTheExercise() {
        let sets = makeBenchPress(loads: ["RPE6", "RPE7", "Drop 20%"]).sets.sorted { $0.index < $1.index }
        sets[0].markLogged(SetLog(weight: .pounds(185), reps: 5, rpe: .seven), at: Date(timeIntervalSinceReferenceDate: 0))
        sets[1].markLogged(SetLog(weight: .pounds(225), reps: 5, rpe: .eight), at: Date(timeIntervalSinceReferenceDate: 60))

        #expect(LoadSuggestionEngine.suggest(for: sets[2], history: .empty) == .prescribedWeight(180))
    }

    @Test func aSetHoldingASetLogConsultsNothing() {
        let set = makeBenchPress(loads: ["RPE6"]).sets[0]
        set.markLogged(SetLog(weight: .pounds(185), reps: 5, rpe: .seven), at: Date(timeIntervalSinceReferenceDate: 0))

        #expect(LoadSuggestionEngine.suggest(for: set, history: historyWithTheSetsOwnSession) == .noSuggestion)
    }
}
