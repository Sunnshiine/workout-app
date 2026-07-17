import Testing

@testable import WorkoutTracker

@MainActor
@Test func weightPillPrefillsFromLoadSuggestion() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE6", percentOneRM: "75%", state: .pending),
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
    #expect(amrap.repsDisplay == "AMRAP")
}

@MainActor
@Test func repsPillShowsNonIntegerPrescriptionAsHint() {
    let range = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "10-15", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    let amrap = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(range.repsText == "")
    #expect(range.repsDisplay == "10-15")
    #expect(range.isRepsDisplayingPlaceholder)
    #expect(amrap.repsText == "")
    #expect(amrap.repsDisplay == "AMRAP")
    #expect(amrap.isRepsDisplayingPlaceholder)
}

@MainActor
@Test func fineWeightIncrementIsTwoAndAHalfUnderThresholdAndFiveAtOrAboveIt() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    form.weightText = "100"
    #expect(form.fineWeightIncrement == 2.5)

    form.weightText = "100.5"
    #expect(form.fineWeightIncrement == 5)
}

@MainActor
@Test func weightSteppingIsHiddenUntilThereIsANumericWeight() {
    var bodyweight = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    #expect(!bodyweight.allowsWeightStepping)

    bodyweight.weightText = "135"
    #expect(bodyweight.allowsWeightStepping)

    bodyweight.weightText = ""
    #expect(!bodyweight.allowsWeightStepping)

    bodyweight.weightText = "nan"
    #expect(!bodyweight.allowsWeightStepping)

    bodyweight.weightText = "inf"
    #expect(!bodyweight.allowsWeightStepping)
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
@Test func rpeGridHalfStepLabelsKeepWholeGridAndOnlySupportSixThroughNine() {
    let grid = RPEGridPresentation(prescribedRPE: 8)
    let values = grid.rows.flatMap { $0 }

    #expect(values.map(\.value) == [5, 6, 7, 8, 9, 10])
    #expect(values.map(\.halfStepLabel) == [nil, "6.5", "7.5", "8.5", "9.5", nil])
}

@MainActor
@Test func logButtonPreviewUpdatesAndRequiresCompleteSetLog() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    form.weightText = "185"

    #expect(form.logButtonTitle == "Choose RPE to log")
    #expect(!form.canLog)

    form.rpeText = "7"

    #expect(form.logButtonTitle == "Log 185×8@7")
    #expect(form.canLog)
    #expect(form.makeLog() == SetLog(weight: .pounds(185), reps: 8, rpe: 7))
}

@MainActor
@Test func logButtonTitleUsesGenericIncompletePromptWhenMultipleFieldsAreMissing() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.logButtonTitle == "Complete Set Log")
    #expect(!form.canLog)
}

@MainActor
@Test func formValidationMarksInvalidFieldsAndClearsThemAsTheyBecomeValid() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "10-15", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.invalidFields.isEmpty)
    #expect(form.markInvalidFieldsForDisplay() == [.weight, .reps, .rpe])
    #expect(form.invalidFields == [.weight, .reps, .rpe])

    form.weightText = "182.5"
    #expect(form.invalidFields == [.reps, .rpe])

    form.repsText = "12"
    #expect(form.invalidFields == [.rpe])

    form.rpeText = "7.5"
    #expect(form.invalidFields.isEmpty)
    #expect(form.makeLog() == SetLog(weight: .pounds(182.5), reps: 12, rpe: 7.5))
}

@MainActor
@Test func selectedRPEStateCanMoveFromHalfStepBackToWholeStep() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 6", percentOneRM: "95%", state: .pending),
        previousSetWeight: nil,
        trainingMax: 250
    )

    form.rpeText = "6.5"
    #expect(form.logButtonTitle == "Log 237.5×5@6.5")

    form.rpeText = "6"
    #expect(form.rpeDisplay == "6")
    #expect(form.makeLog() == SetLog(weight: .pounds(237.5), reps: 5, rpe: 6))
}

@MainActor
@Test func submittingInvalidLogMarksInvalidFieldsWithoutProducingLog() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )

    #expect(form.submitLog() == nil)
    #expect(form.invalidFields == [.weight, .reps, .rpe])

    form.weightText = "BW"
    form.repsText = "12"
    form.rpeText = "7"

    #expect(form.invalidFields.isEmpty)
    #expect(form.submitLog() == SetLog(weight: .bodyweight, reps: 12, rpe: 7))
}

@MainActor
@Test func logFormAcceptsOnlyBodyweightOrFiniteWeightIntegerRepsAndFiveToTenHalfStepRPE() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        previousSetWeight: nil,
        trainingMax: nil
    )
    form.repsText = "8"
    form.rpeText = "5"
    #expect(form.makeLog() == SetLog(weight: .bodyweight, reps: 8, rpe: 5))

    form.weightText = "182.5"
    form.rpeText = "10"
    #expect(form.makeLog() == SetLog(weight: .pounds(182.5), reps: 8, rpe: 10))

    form.weightText = "nan"
    #expect(form.makeLog() == nil)
    #expect(form.markInvalidFieldsForDisplay() == [.weight])
    form.weightText = "182.5"

    form.repsText = "8.5"
    #expect(form.makeLog() == nil)
    #expect(form.invalidFields == [.reps])
    form.repsText = "8"

    form.rpeText = "4.5"
    #expect(form.makeLog() == nil)
    #expect(form.invalidFields == [.rpe])
    form.rpeText = "7.25"
    #expect(form.makeLog() == nil)
    #expect(form.invalidFields == [.rpe])
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

    let suggestedSet = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: "75%", state: .pending)
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

@MainActor
@Test func rpePrefillsFromPrescribedSoLogIsReadyImmediately() {
    // Percent column resolves the weight and the RPE column pre-fills RPE, so a
    // freshly-focused set can be logged at the prescription with a single tap.
    let prescribed = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: "75%", state: .pending),
        previousSetWeight: nil,
        trainingMax: 265
    )

    #expect(prescribed.rpeText == "8")
    #expect(prescribed.canLog)

    let noPrescribedRPE = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: "75%", state: .pending),
        previousSetWeight: nil,
        trainingMax: 265
    )

    #expect(noPrescribedRPE.rpeText == "")
}
