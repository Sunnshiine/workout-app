import Testing

@testable import WorkoutTracker

/// The engine's inputs as the old four-argument call named them: a `previousSetWeight` is the one
/// Set logged just before this one.
private func suggest(
    prescribedLoad: String,
    percentOneRM: String?,
    previousSetWeight: Double?,
    trainingMax: Double?
) -> LoadSuggestion {
    LoadSuggestionEngine.suggest(
        LoadSuggestionInputs(
            prescribedReps: "5",
            prescribedLoad: prescribedLoad,
            percentOneRM: percentOneRM,
            trainingMax: trainingMax,
            earlierSets: previousSetWeight.map { [(index: 0, setLog: SetLog(weight: .pounds($0), reps: 5, rpe: .eight))] } ?? []
        )
    )
}

private func dropSuggestion(after earlierSets: [(index: Int, setLog: SetLog)]) -> LoadSuggestion {
    LoadSuggestionEngine.suggest(
        LoadSuggestionInputs(
            prescribedReps: "5",
            prescribedLoad: "Drop 20%",
            percentOneRM: nil,
            trainingMax: nil,
            earlierSets: earlierSets
        )
    )
}

private func logged(_ weight: Weight) -> SetLog {
    SetLog(weight: weight, reps: 5, rpe: .eight)
}

@Test func suggestsLoadForDropPrescriptionFromPreviousSetWeight() {
    #expect(
        suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: nil
        ) == .weight(185)
    )
}

@Test func suggestsLoadForPercentOneRMPrescriptionFromTrainingMax() {
    #expect(
        suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: 265
        ) == .weight(200)
    )
}

@Test func roundsLoadSuggestionToNearestPlateIncrement() {
    #expect(
        suggest(
            prescribedLoad: "Drop 12%",
            percentOneRM: nil,
            previousSetWeight: 185,
            trainingMax: nil
        ) == .weight(162.5)
    )
}

@Test func bodyweightPrescriptionPreFillsBodyweight() {
    #expect(
        suggest(
            prescribedLoad: "BW",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: nil
        ) == .bodyweight
    )
}

@Test func bodyweightWinsOverAPresentPercentOneRM() {
    #expect(
        suggest(
            prescribedLoad: "BW",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: 265
        ) == .bodyweight
    )
}

@Test("Unsupported Prescribed Load returns no Load Suggestion", arguments: ["RPE 6", "RPE6", "Start conservative"])
func unsupportedPrescribedLoadReturnsNone(prescribedLoad: String) {
    #expect(
        suggest(
            prescribedLoad: prescribedLoad,
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: 265
        ) == .noSuggestion
    )
}

@Test func missingContextReturnsNoneForLoadSuggestion() {
    #expect(
        suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: 265
        ) == .noSuggestion
    )
    #expect(
        suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: 225,
            trainingMax: nil
        ) == .noSuggestion
    )
}

@Test func dropReadsTheNearestEarlierSetByIndexInAnyOrder() {
    #expect(dropSuggestion(after: [(index: 1, setLog: logged(.pounds(225))), (index: 0, setLog: logged(.pounds(185)))]) == .weight(180))
}

@Test func dropPassesOverABodyweightSetToTheNextOneBack() {
    #expect(dropSuggestion(after: [(index: 0, setLog: logged(.pounds(185))), (index: 1, setLog: logged(.bodyweight))]) == .weight(147.5))
}

@Test func dropOnTheFirstSetHasNothingToDropFrom() {
    #expect(dropSuggestion(after: []) == .noSuggestion)
}
