import Foundation
import Testing

@testable import WorkoutTracker

private func benchHistory(_ entries: [(resultText: String, source: String)]) -> LastPerformedLookupSnapshot {
    LastPerformedLookupSnapshot(
        occurrences: entries.map {
            LastPerformedOccurrence(
                exerciseName: "Bench Press",
                resultText: $0.resultText,
                performedOn: Date(timeIntervalSinceReferenceDate: 0),
                source: $0.source
            )
        }
    )
}

@MainActor
private func cardForm(_ set: ExerciseSet, history: [(resultText: String, source: String)]) -> SmartValuePillsForm {
    SmartValuePillsForm(set: set, suggestion: LoadSuggestionEngine.suggest(for: set, history: benchHistory(history)))
}

@MainActor
@Test func anEstimateFromAnotherBlockNamesItsBlockAndSession() {
    let set = makeBenchPress(loads: ["RPE6"]).sets[0]

    let form = cardForm(set, history: [("185x5@7, 195x5@8", "Block 26 · W4 D1")])

    #expect(form.weightText == "182.5")
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · Block 26 W4 D1", isShown: true))
}

@MainActor
@Test func anEstimateFromTheSameBlockNamesOnlyItsSession() {
    let set = makeBenchPress(loads: ["RPE7"], at: SessionAddress(week: 2, day: 1)).sets[0]

    let form = cardForm(set, history: [("315x5@7, 295x5@6", "Block 27 · W1 D1")])

    #expect(form.weightText == "315")
    #expect(form.loadBasisLine == .init(text: "from 315x5@7 · W1 D1", isShown: true))
}

@MainActor
private func competitionBenchPress() -> Exercise {
    makeBenchPress(named: "Competition Bench Press", loads: ["RPE6"], at: SessionAddress(week: 2, day: 2))
}

private func competitionBenchHistory(name: ExerciseName) -> LastPerformedLookupSnapshot {
    LastPerformedLookupSnapshot(occurrences: [
        LastPerformedOccurrence(
            exerciseName: name,
            resultText: "185x5@7, 195x5@8",
            performedOn: Date(timeIntervalSinceReferenceDate: 0),
            source: "Block 27 · W1 D2"
        )
    ])
}

@MainActor
private func estimateForm(_ exercise: Exercise, history: LastPerformedLookupSnapshot) -> SmartValuePillsForm {
    SmartValuePillsForm(set: exercise.sets[0], suggestion: LoadSuggestionEngine.suggest(for: exercise.sets[0], history: history))
}

@MainActor
@Test func anEstimateFromAMovementLevelMatchNamesTheEntryItCameFrom() {
    let history = competitionBenchHistory(name: "Comp Bench Press")

    let form = estimateForm(competitionBenchPress(), history: history)

    #expect(form.weightText == "182.5")
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · W1 D2 as “Comp Bench Press”", isShown: true))
}

@MainActor
@Test func aCaseOnlyMovementLevelMatchNamesTheEntryAsLastPerformedDoes() {
    let exercise = competitionBenchPress()
    let history = competitionBenchHistory(name: "competition bench press")

    let form = estimateForm(exercise, history: history)

    #expect(form.weightText == "182.5")
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · W1 D2 as “competition bench press”", isShown: true))
    #expect(LastPerformedCardPresentation(exercise: exercise, lookup: history)?.matchedName == "competition bench press")
}

@MainActor
@Test func anEstimateFromAnEntryWithTheExercisesBaseNameNamesNoEntry() {
    let history = competitionBenchHistory(name: "2-0:1:0 Competition Bench Press")

    let form = estimateForm(competitionBenchPress(), history: history)

    #expect(form.weightText == "182.5")
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · W1 D2", isShown: true))
}

@MainActor
@Test func anEstimateFromAnEarlierSetNamesItAsToday() {
    let sets = makeBenchPress(loads: ["RPE6", "RPE7"]).sets.sorted { $0.index < $1.index }
    sets[0].markLogged(SetLog(weight: .pounds(185), reps: 5, rpe: .seven), at: Date(timeIntervalSinceReferenceDate: 0))

    let form = cardForm(sets[1], history: [("185x5@7, 195x5@8", "Block 26 · W4 D1")])

    #expect(form.weightText == "185")
    #expect(form.loadBasisLine == .init(text: "from Set 1 today", isShown: true))
}

@MainActor
@Test func overridingTheEstimatedWeightHidesTheLoadBasisLineButKeepsItsSpace() {
    let set = makeBenchPress(loads: ["RPE6"]).sets[0]
    var form = cardForm(set, history: [("185x5@7, 195x5@8", "Block 26 · W4 D1")])

    form.stepWeight(.up)
    #expect(form.weightText == "187.5")
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · Block 26 W4 D1", isShown: false))

    form.cancel()
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · Block 26 W4 D1", isShown: true))
}

@MainActor
@Test func aLaterSuggestionReplacesAnUntouchedPrefillAndItsBasisLine() {
    let set = makeBenchPress(loads: ["RPE6"]).sets[0]
    var form = SmartValuePillsForm(set: set, suggestion: LoadSuggestionEngine.suggest(for: set, history: .empty))
    #expect(form.weightText == "")

    form.refreshPrefill(
        from: LoadSuggestionEngine.suggest(for: set, history: benchHistory([("185x5@7, 195x5@8", "Block 26 · W4 D1")])),
        for: set
    )

    #expect(form.weightText == "182.5")
    #expect(form.loadBasisLine == .init(text: "from 195x5@8 · Block 26 W4 D1", isShown: true))
    #expect(form.hasChanges == false)
}

@MainActor
@Test func aLaterSuggestionLeavesAnOverriddenWeightAlone() {
    let set = makeBenchPress(loads: ["RPE6"]).sets[0]
    var form = SmartValuePillsForm(set: set, suggestion: LoadSuggestionEngine.suggest(for: set, history: .empty))
    form.weightText = "205"

    form.refreshPrefill(
        from: LoadSuggestionEngine.suggest(for: set, history: benchHistory([("185x5@7, 195x5@8", "Block 26 · W4 D1")])),
        for: set
    )

    #expect(form.weightText == "205")
    #expect(form.loadBasisLine == nil)
}

@MainActor
@Test func aLaterSuggestionLeavesALoggedSetsWeightAlone() {
    let set = makeBenchPress(loads: ["RPE6"]).sets[0]
    set.markLogged(SetLog(weight: .pounds(185), reps: 5, rpe: .seven), at: Date(timeIntervalSinceReferenceDate: 0))
    var form = SmartValuePillsForm(set: set, suggestion: .noSuggestion)

    form.refreshPrefill(from: .prescribedWeight(200), for: set)

    #expect(form.weightText == "185")
}
