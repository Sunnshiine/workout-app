import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func weightPillPrefillsFromLoadSuggestion() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .pending),
        suggestion: .prescribedWeight(200)
    )

    #expect(form.weightText == "200")
    #expect(form.weightDisplay == "200")
}

@MainActor
@Test func weightPillPrefillsBodyweightPrescription() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        suggestion: .bodyweight
    )

    #expect(form.weightText == "BW")
    #expect(form.weightDisplay == "BW")
}

@MainActor
@Test func weightPillShowsDashWhenDropPercentCannotCalculateYet() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "Drop 17.5%", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )

    #expect(form.weightText == "")
    #expect(form.weightDisplay == "—")
}

@MainActor
@Test func weightPillRendersADropSuggestionPastIntRangeInsteadOfTrapping() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "Drop 50%", percentOneRM: nil, state: .pending),
        suggestion: .prescribedWeight(1e19)
    )

    #expect(form.weightText == "1e+19")
}

@MainActor
@Test func repsPillPrefillsPrescribedRepsAndLeavesAMRAPEmpty() {
    let prescribed = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )
    let amrap = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        suggestion: .bodyweight
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
        suggestion: .noSuggestion
    )
    let amrap = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        suggestion: .bodyweight
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
        suggestion: .noSuggestion
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
        suggestion: .bodyweight
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
        suggestion: .noSuggestion
    )
    form.weightText = "95"

    form.adjustWeight(by: 2.5)
    #expect(form.weightText == "97.5")

    form.adjustWeight(by: -5)
    #expect(form.weightText == "92.5")
}

@MainActor
@Test func logButtonPreviewUpdatesAndRequiresCompleteSetLog() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )
    form.weightText = "185"

    #expect(form.logButtonTitle == "Choose RPE to log")
    #expect(!form.canLog)

    form.rpeText = "7"

    #expect(form.logButtonTitle == "Log 185 × 8 @7")
    #expect(form.canLog)
    #expect(form.makeLog() == SetLog(weight: .pounds(185), reps: 8, rpe: .seven))
}

@MainActor
@Test func logButtonTitleUsesGenericIncompletePromptWhenMultipleFieldsAreMissing() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )

    #expect(form.logButtonTitle == "Complete Set Log")
    #expect(!form.canLog)
}

@MainActor
@Test func formValidationMarksInvalidFieldsAndClearsThemAsTheyBecomeValid() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "10-15", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
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
    #expect(form.makeLog() == SetLog(weight: .pounds(182.5), reps: 12, rpe: .sevenPointFive))
}

@MainActor
@Test func selectedRPEStateCanMoveFromHalfStepBackToWholeStep() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 6", percentOneRM: "95%", state: .pending),
        suggestion: .prescribedWeight(237.5)
    )

    form.rpeText = "6.5"
    #expect(form.logButtonTitle == "Log 237.5 × 5 @6.5")

    form.rpeText = "6"
    #expect(form.rpeDisplay == "6")
    #expect(form.makeLog() == SetLog(weight: .pounds(237.5), reps: 5, rpe: .six))
}

@MainActor
@Test func loggedHalfPointRPEPrefillsWithItsDecimalLabel() {
    let loggedSet = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    loggedSet.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: .sixPointFive)

    let form = SmartValuePillsForm(set: loggedSet, suggestion: .noSuggestion)

    #expect(form.rpeText == "6.5")
    #expect(form.logButtonTitle == "Log 185 × 5 @6.5")
}

@MainActor
@Test func prescribedRPEPrefillReadsTheRPEPrefixInAnyCasingAndSpacing() {
    func prefill(_ prescribedLoad: String) -> String {
        SmartValuePillsForm(
            set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: prescribedLoad, percentOneRM: nil, state: .pending),
            suggestion: .noSuggestion
        ).rpeText
    }

    #expect(prefill("RPE6") == "6")
    #expect(prefill(" rpe 8 ") == "8")
    #expect(prefill("RPE 6.5") == "6.5")
    #expect(prefill("RPE 5.5") == "")
    #expect(prefill("Drop 10%") == "")
    #expect(prefill("BW") == "")
    #expect(prefill("72.5") == "")
    #expect(prefill("RPE") == "")
}

@MainActor
@Test func submittingInvalidLogMarksInvalidFieldsWithoutProducingLog() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "AMRAP", prescribedLoad: "75%1RM", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )

    #expect(form.submitLog() == nil)
    #expect(form.invalidFields == [.weight, .reps, .rpe])

    form.weightText = "BW"
    form.repsText = "12"
    form.rpeText = "7"

    #expect(form.invalidFields.isEmpty)
    #expect(form.submitLog() == SetLog(weight: .bodyweight, reps: 12, rpe: .seven))
}

@MainActor
@Test func logFormAcceptsOnlyBodyweightOrFiniteWeightIntegerRepsAndRailPointRPE() {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "BW", percentOneRM: nil, state: .pending),
        suggestion: .bodyweight
    )
    form.repsText = "8"
    form.rpeText = "5"
    #expect(form.makeLog() == SetLog(weight: .bodyweight, reps: 8, rpe: .five))

    form.weightText = "182.5"
    form.rpeText = "10"
    #expect(form.makeLog() == SetLog(weight: .pounds(182.5), reps: 8, rpe: .ten))

    form.weightText = "nan"
    #expect(form.makeLog() == nil)
    #expect(form.markInvalidFieldsForDisplay() == [.weight])
    form.weightText = "182.5"

    form.repsText = "8.5"
    #expect(form.makeLog() == nil)
    #expect(form.invalidFields == [.reps])
    form.repsText = "8"

    form.rpeText = "5.5"
    #expect(form.makeLog() == nil)
    #expect(form.invalidFields == [.rpe])

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
    loggedSet.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: .eight)
    var logged = SmartValuePillsForm(set: loggedSet, suggestion: .noSuggestion)
    logged.weightText = "200"
    logged.repsText = "9"
    logged.rpeText = "9"

    logged.cancel()

    #expect(logged.weightText == "185")
    #expect(logged.repsText == "7")
    #expect(logged.rpeText == "8")

    let suggestedSet = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: "75%", state: .pending)
    var suggested = SmartValuePillsForm(set: suggestedSet, suggestion: .prescribedWeight(200))
    suggested.weightText = "190"

    suggested.cancel()

    #expect(suggested.weightText == "200")
    #expect(suggested.repsText == "5")
    #expect(suggested.rpeText == "")
}

@MainActor
@Test func loggedSetDraftOnlyProducesChangedValidLog() {
    let loggedSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    loggedSet.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: .eight)
    var form = SmartValuePillsForm(set: loggedSet, suggestion: .noSuggestion)

    #expect(form.changedValidLog == nil)

    form.weightText = "200"

    #expect(form.changedValidLog == SetLog(weight: .pounds(200), reps: 7, rpe: .eight))

    form.rpeText = ""

    #expect(form.changedValidLog == nil)
}

@MainActor
@Test func prescribedRPEComesFromPrescribedLoad() {
    let form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )

    #expect(form.prescribedRPE == .eight)
}

@MainActor
@Test func rpePrefillsFromPrescribedSoLogIsReadyImmediately() {
    // Percent column resolves the weight and the RPE column pre-fills RPE, so a
    // freshly-focused set can be logged at the prescription with a single tap.
    let prescribed = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: "75%", state: .pending),
        suggestion: .prescribedWeight(200)
    )

    #expect(prescribed.rpeText == "8")
    #expect(prescribed.canLog)

    let noPrescribedRPE = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: "75%", state: .pending),
        suggestion: .prescribedWeight(200)
    )

    #expect(noPrescribedRPE.rpeText == "")
}

@MainActor
private func stepForm(weight: String) -> SmartValuePillsForm {
    var form = SmartValuePillsForm(
        set: ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending),
        suggestion: .noSuggestion
    )
    form.weightText = weight
    return form
}

@MainActor
@Test func stepWeightAddsAndSubtractsTheFineIncrementWithoutHittingTheFloor() {
    var form = stepForm(weight: "185")
    #expect(form.fineWeightIncrement == 5)

    #expect(form.stepWeight(.up) == false)
    #expect(form.weightText == "190")

    #expect(form.stepWeight(.down) == false)
    #expect(form.weightText == "185")
}

@MainActor
@Test func stepWeightLandingExactlyOnZeroIsANormalStepNotAFloorHit() {
    var form = stepForm(weight: "2.5")

    // 2.5 − 2.5 == 0 exactly: a valid step down to zero, so no floor hit (the tick, not the dud).
    #expect(form.stepWeight(.down) == false)
    #expect(form.weightText == "0")
}

@MainActor
@Test func stepWeightClampsAWouldBeNegativeDecrementToZeroAndReportsTheFloorHit() {
    var form = stepForm(weight: "0")

    // 0 − 2.5 < 0: clamp to 0 and report the floor hit so the caller plays the dud.
    #expect(form.stepWeight(.down) == true)
    #expect(form.weightText == "0")
}

@MainActor
@Test func stepWeightRendersAWeightPastIntRangeInsteadOfTrapping() {
    var form = stepForm(weight: "1e19")

    form.stepWeight(.up)
    #expect(form.weightText == "1e+19")
}

private func benchHistory(_ entries: [(resultText: String, source: String)]) -> LastPerformedLookupSnapshot {
    LastPerformedLookupSnapshot(
        occurrences: entries.map {
            LastPerformedOccurrence(
                fullName: "Bench Press",
                baseName: "Bench Press",
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
