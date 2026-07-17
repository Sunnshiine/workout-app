import Testing

@testable import WorkoutTracker

@Test func suggestsLoadForDropPrescriptionFromPreviousSetWeight() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: nil
        ) == .weight(185)
    )
}

@Test func suggestsLoadForPercentOneRMPrescriptionFromTrainingMax() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: 265
        ) == .weight(200)
    )
}

@Test func roundsLoadSuggestionToNearestPlateIncrement() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "Drop 12%",
            percentOneRM: nil,
            previousSetWeight: 185,
            trainingMax: nil
        ) == .weight(162.5)
    )
}

@Test func bodyweightPrescriptionPreFillsBodyweight() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "BW",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: nil
        ) == .bodyweight
    )
}

@Test func bodyweightWinsOverAPresentPercentOneRM() {
    #expect(
        LoadSuggestionEngine.suggest(
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
        LoadSuggestionEngine.suggest(
            prescribedLoad: prescribedLoad,
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: 265
        ) == .none
    )
}

@Test func missingContextReturnsNoneForLoadSuggestion() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: 265
        ) == .none
    )
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: 225,
            trainingMax: nil
        ) == .none
    )
}
