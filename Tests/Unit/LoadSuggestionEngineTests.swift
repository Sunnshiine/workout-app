import Testing

@testable import WorkoutTracker

@Test func suggestsLoadForDropPrescriptionFromPreviousSetWeight() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: nil
        ) == 185
    )
}

@Test func suggestsLoadForPercentOneRMPrescriptionFromTrainingMax() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: 265
        ) == 200
    )
}

@Test func roundsLoadSuggestionToNearestPlateIncrement() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "Drop 12%",
            percentOneRM: nil,
            previousSetWeight: 185,
            trainingMax: nil
        ) == 162.5
    )
}

@Test("Unsupported Prescribed Load returns no Load Suggestion", arguments: ["RPE 6", "RPE6", "BW", "Start conservative"])
func unsupportedPrescribedLoadReturnsNil(prescribedLoad: String) {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: prescribedLoad,
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: 265
        ) == nil
    )
}

@Test func missingContextReturnsNilForLoadSuggestion() {
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: 265
        ) == nil
    )
    #expect(
        LoadSuggestionEngine.suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: 225,
            trainingMax: nil
        ) == nil
    )
}
