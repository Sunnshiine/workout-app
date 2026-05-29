import Testing

@testable import WorkoutTracker

@MainActor
@Test func weightPillPrefillsFromLoadSuggestion() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: 265
    )

    #expect(form.weightText == "200")
    #expect(form.weightDisplay == "200")
}

@MainActor
@Test func weightPillUsesPercentOneRMColumnForLoadSuggestion() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE6", percentOneRM: "75%", state: .pending),
        previousSetWeight: nil,
        trainingMax: 265
    )

    #expect(form.weightText == "200")
}

@MainActor
@Test func weightPillPrefillsBodyweightPrescription() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.weightText == "BW")
    #expect(form.weightDisplay == "BW")
}

@MainActor
@Test func weightPillShowsDashWhenDropPercentCannotCalculateYet() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "Drop 17.5%", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.weightText == "")
    #expect(form.weightDisplay == "—")
}

@MainActor
@Test func repsPillPrefillsPrescribedRepsAndLeavesAMRAPEmpty() {
    let prescribed = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    let amrap = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(prescribed.repsText == "8")
    #expect(prescribed.repsDisplay == "8")
    #expect(amrap.repsText == "")
    #expect(amrap.repsDisplay == "—")
}

@MainActor
@Test func weightIncrementOptionsUseGymFriendlyThreshold() {
    var light = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    light.weightText = "100"
    var heavy = light
    heavy.weightText = "100.5"

    #expect(light.weightIncrementOptions == [2.5, 5])
    #expect(heavy.weightIncrementOptions == [5, 10])
}

@MainActor
@Test func weightIncrementButtonsAdjustCurrentWeight() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    form.weightText = "95"

    form.adjustWeight(by: 2.5)
    #expect(form.weightText == "97.5")

    form.adjustWeight(by: -5)
    #expect(form.weightText == "92.5")
}

@MainActor
@Test func rpeGridUsesTwoRowsDimsFiveAndMarksPrescribedRPE() {
    let grid = RPEGridPresentation(prescribedRPE: 8)

    #expect(grid.rows.map { $0.map(\.value) } == [[5, 6, 7], [8, 9, 10]])
    #expect(grid.rows[0][0].isDimmed)
    #expect(grid.rows[1][0].showsPrescriptionBadge)
    #expect(grid.autoCloseDelay == .milliseconds(300))
}

@MainActor
@Test func logButtonPreviewUpdatesAndRequiresCompleteSetLog() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.logButtonTitle == "Log")
    #expect(!form.canLog)

    form.weightText = "185"
    form.rpeText = "7"

    #expect(form.logButtonTitle == "Log 185×8@7")
    #expect(form.canLog)
    #expect(form.makeLog() == SetLog(weight: .pounds(185), reps: 8, rpe: 7))
}

@MainActor
@Test func cancelRestoresLoggedSetOrSuggestionState() {
    let loggedSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    loggedSet.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: 8)
    var logged = SmartValuePillsForm(set: loggedSet, previousSetWeight: nil, trainingMax: nil)
    logged.weightText = "200"
    logged.repsText = "9"
    logged.rpeText = "9"

    logged.cancel()

    #expect(logged.weightText == "185")
    #expect(logged.repsText == "7")
    #expect(logged.rpeText == "8")

    let suggestedSet = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending)
    var suggested = SmartValuePillsForm(set: suggestedSet, previousSetWeight: nil, trainingMax: 265)
    suggested.weightText = "190"

    suggested.cancel()

    #expect(suggested.weightText == "200")
    #expect(suggested.repsText == "5")
    #expect(suggested.rpeText == "")
}

@MainActor
@Test func loggedSetDraftOnlyProducesChangedValidLog() {
    let loggedSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    loggedSet.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: 8)
    var form = SmartValuePillsForm(set: loggedSet, previousSetWeight: nil, trainingMax: nil)

    #expect(form.changedValidLog == nil)

    form.weightText = "200"

    #expect(form.changedValidLog == SetLog(weight: .pounds(200), reps: 7, rpe: 8))

    form.rpeText = ""

    #expect(form.changedValidLog == nil)
}

@MainActor
@Test func prescribedRPEComesFromPrescribedLoad() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.prescribedRPE == 8)
}
