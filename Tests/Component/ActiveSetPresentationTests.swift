import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func activeSetPresentationContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "active-set-presentation-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@Test func holdToSkipPolicyDefaultsToTheTokenizedTimings() {
    // Ledger §1.4: the tokenized timings are the policy's source of truth — reveal 250ms, commit
    // 850ms — retiring the hardcoded 0.8s. Logged and skipped Sets hold longer (900ms / 1100ms).
    let standard = HoldToSkipPolicy()
    #expect(standard.holdDuration == Theme.Motion.holdToSkipCommit)
    #expect(standard.holdDuration == 0.85)
    #expect(standard.revealDelay == Theme.Motion.holdToSkipReveal)
    #expect(standard.revealDelay == 0.25)
    #expect(HoldToSkipPolicy.standard == standard)
    #expect(HoldToSkipPolicy.loggedState.holdDuration == 0.9)
    #expect(HoldToSkipPolicy.skippedState.holdDuration == 1.1)
}

@Test func holdToSkipPolicyDefersQuickReleaseToButtonTap() {
    let policy = HoldToSkipPolicy(holdDuration: 0.8, tapMaximumDuration: 0.18, revealDelay: 0.25)

    let outcome = policy.releaseOutcome(elapsed: 0.1, skipCompleted: false)

    #expect(outcome == .deferToTap)
    #expect(!policy.shouldRevealProgress(elapsed: 0.1))

    let presentation = HoldToSkipButtonPresentation(progress: 0, logTitle: "Log 185×5@8")
    #expect(presentation.logOpacity == 1)
    #expect(presentation.skipOpacity == 0)
    #expect(presentation.accessibilityLabel == "Log 185×5@8")
    #expect(presentation.tone == .primary)
}

@Test func holdToSkipPolicyDoesNotTreatCanceledHoldAsLogTap() {
    let policy = HoldToSkipPolicy(holdDuration: 0.8, tapMaximumDuration: 0.18, revealDelay: 0.25)

    #expect(policy.releaseOutcome(elapsed: 0.19, skipCompleted: false) == .cancelSkip)
    #expect(policy.releaseOutcome(elapsed: 0.4, skipCompleted: false) == .cancelSkip)
}

@Test func holdToSkipPolicyCancelsSkipOnEarlyHoldRelease() {
    let policy = HoldToSkipPolicy(holdDuration: 0.8, tapMaximumDuration: 0.18, revealDelay: 0.25)

    let outcome = policy.releaseOutcome(elapsed: 0.4, skipCompleted: false)

    #expect(outcome == .cancelSkip)
}

@Test func holdToSkipPolicyRevealsProgressOnlyAfterDelay() {
    let policy = HoldToSkipPolicy(holdDuration: 0.8, tapMaximumDuration: 0.18, revealDelay: 0.25)

    #expect(!policy.shouldRevealProgress(elapsed: 0.249))
    #expect(policy.shouldRevealProgress(elapsed: 0.25))
    #expect(policy.progressAnimationDuration == 0.55)
}

@Test func holdToSkipPolicyIgnoresReleaseAfterCompletedSkip() {
    let policy = HoldToSkipPolicy(holdDuration: 0.8, tapMaximumDuration: 0.18, revealDelay: 0.25)

    let outcome = policy.releaseOutcome(elapsed: 0.9, skipCompleted: true)

    #expect(outcome == .ignore)
}

@Test func holdToSkipPolicyCompletesSkipWhenReleaseReachesHoldDuration() {
    let policy = HoldToSkipPolicy(holdDuration: 0.8, tapMaximumDuration: 0.18, revealDelay: 0.25)

    let outcome = policy.releaseOutcome(elapsed: 0.9, skipCompleted: false)

    #expect(outcome == .skip)
}

@Test func holdToSkipButtonPresentationFadesTowardSkippedState() {
    let presentation = HoldToSkipButtonPresentation(progress: 0.65, logTitle: "Log 185×5@8")

    #expect(abs(presentation.logOpacity - 0.35) < 0.001)
    #expect(abs(presentation.skipOpacity - 0.65) < 0.001)
    #expect(presentation.accessibilityLabel == "Skipped")
}

@Test func holdToSkipButtonPresentationKeepsIncompleteLogIdleStateClean() {
    let presentation = HoldToSkipButtonPresentation(progress: 0, logTitle: "Choose RPE to log", canLog: false)

    #expect(presentation.controlOpacity == 1)
    #expect(!presentation.showsSkipAffordance)
    #expect(presentation.skipOpacity == 0)
    #expect(presentation.tone == .incomplete)
    #expect(presentation.accessibilityHint == "Double tap to show what is missing. Press and hold to skip this Set.")
}

@Test func holdToSkipButtonPresentationShowsSkippedFeedbackOnlyDuringHoldProgress() {
    let presentation = HoldToSkipButtonPresentation(progress: 0.65, logTitle: "Log", canLog: false)

    #expect(!presentation.showsSkipAffordance)
    #expect(abs(presentation.skipOpacity - 0.65) < 0.001)
    #expect(presentation.accessibilityLabel == "Skipped")
}

@MainActor
@Test func setRowPresentationShowsLoggedSetWithAccentAndCheckmark() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
    set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "185x5@8")
    #expect(presentation.tone == .accent)
    #expect(presentation.showsCheckmark)
}

@MainActor
@Test func setRowPresentationShowsSkippedSetAsMutedSkip() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "skip")
    #expect(presentation.tone == .muted)
    #expect(!presentation.showsCheckmark)
}

@MainActor
@Test func setRowPresentationShowsPendingSetAsMutedPrescription() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "5 · RPE 8")
    #expect(presentation.tone == .muted)
    #expect(!presentation.showsCheckmark)
}

@MainActor
@Test func setCardLoggingModeShowsLogControlsAndNeverAutoCommits() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)

    let presentation = SetCardPresentation(mode: .logging, set: set)

    #expect(presentation.statusText == "Up next")
    #expect(presentation.referenceText == nil)
    #expect(presentation.showsLogControls)
    #expect(!presentation.commitsChangesOnDisappear)
}

@MainActor
@Test func setCardReviewModeHidesLogControlsAndCommitsChangesOnDisappear() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
    set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    let presentation = SetCardPresentation(mode: .reviewingLogged, set: set)

    #expect(presentation.statusText == "Set Log")
    #expect(presentation.referenceText == nil)
    #expect(!presentation.showsLogControls)
    #expect(presentation.commitsChangesOnDisappear)
}

@MainActor
@Test func setCardReviewModeKeepsUnstructuredLogTextAsReference() {
    let set = ExerciseSet(index: 1, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .logged)
    set.unstructuredSetLog = "BW and vest for 12"

    let presentation = SetCardPresentation(mode: .reviewingLogged, set: set)

    #expect(presentation.statusText == "Unstructured Set Log")
    #expect(presentation.referenceText == "BW and vest for 12")
    #expect(!presentation.showsLogControls)
    #expect(presentation.commitsChangesOnDisappear)
}

@Test func focusMorphPolicyAnimatesPendingFocusWhenMotionIsAllowed() {
    let policy = SessionFocusMorphPolicy(reduceMotion: false)

    #expect(policy.shouldAnimate(.pendingFocus))
}

@Test func focusMorphPolicyDisablesPendingFocusWhenReduceMotionIsEnabled() {
    let policy = SessionFocusMorphPolicy(reduceMotion: true)

    #expect(!policy.shouldAnimate(.pendingFocus))
}

@Test func focusMorphPolicyAnimatesLoggedReviewOpenWhenMotionIsAllowed() {
    let policy = SessionFocusMorphPolicy(reduceMotion: false)

    #expect(policy.shouldAnimate(.loggedReviewOpen))
}

@Test func focusMorphPolicyDoesNotAnimateLoggedReviewCollapse() {
    let policy = SessionFocusMorphPolicy(reduceMotion: false)

    #expect(!policy.shouldAnimate(.loggedReviewCollapse))
}

@Test func focusMorphPolicyDisablesLoggedReviewOpenWhenReduceMotionIsEnabled() {
    let policy = SessionFocusMorphPolicy(reduceMotion: true)

    #expect(!policy.shouldAnimate(.loggedReviewOpen))
}

@Test func focusMorphPolicyAnimatesSuccessfulSupersetSwitchWhenMotionIsAllowed() {
    let policy = SessionFocusMorphPolicy(reduceMotion: false)

    #expect(policy.shouldAnimate(.supersetSwitchSucceeded))
}

@Test func focusMorphPolicyDoesNotAnimateFailedSupersetSwitch() {
    let policy = SessionFocusMorphPolicy(reduceMotion: false)

    #expect(!policy.shouldAnimate(.supersetSwitchFailed))
}

@Test func focusMorphPolicyDisablesSupersetSwitchWhenReduceMotionIsEnabled() {
    let policy = SessionFocusMorphPolicy(reduceMotion: true)

    #expect(!policy.shouldAnimate(.supersetSwitchSucceeded))
}

@MainActor
@Test func sessionProgressHeaderPresentationShowsCompactLocationAndRemainingCount() {
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    let week = Week(number: 2)
    let session = Session(dayNumber: 3, date: nil)
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped),
        ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE 9", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [exercise]
    week.sessions = [session]
    block.weeks = [week]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.locationText == "W2 D3 ›")
    #expect(presentation.completedSetCount == 2)
    #expect(presentation.totalSetCount == 3)
    #expect(presentation.remainingText == "1 left")
    #expect(presentation.locationActionAccessibilityLabel == "Open Block Overview for Week 2, Day 3")
    #expect(presentation.progressAccessibilityValue == "W2 D3, 1 left")
}

@MainActor
@Test func sessionProgressHeaderPresentationBuildsOrderedRailSegments() {
    let session = Session(dayNumber: 1, date: nil)
    let firstExercise = Exercise(name: "Bench", baseName: "Bench", cadence: nil, coachNote: nil, order: 1)
    firstExercise.sets = [
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped),
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    ]
    let secondExercise = Exercise(name: "Row", baseName: "Row", cadence: nil, coachNote: nil, order: 2)
    secondExercise.sets = [
        ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [secondExercise, firstExercise]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.segments.map(\.state) == [.logged, .skipped, .currentPending, .futurePending])
}

@MainActor
@Test func sessionProgressHeaderPresentationUsesFocusedPendingSetForCurrentSegment() {
    let session = Session(dayNumber: 1, date: nil)
    let exercise = Exercise(name: "Bench", baseName: "Bench", cadence: nil, coachNote: nil, order: 0)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [exercise]

    let presentation = SessionProgressHeaderPresentation(
        session: session,
        activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: 1)
    )

    #expect(presentation.segments.map(\.state) == [.futurePending, .currentPending])
}

@MainActor
@Test func sessionProgressHeaderPresentationMovesCurrentSegmentAfterSupersetSideSwitch() throws {
    let session = Session(dayNumber: 1, date: nil)
    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    let bench = Exercise(name: "Bench", baseName: "Bench", cadence: nil, coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [squat, bench]
    let coordinator = SessionCoordinator(session: session)

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))
    let presentation = SessionProgressHeaderPresentation(
        session: session,
        activeSetID: coordinator.activeSetID
    )

    #expect(presentation.segments.map(\.state) == [.futurePending, .currentPending])
}

@Test func sessionSettingsOverpullStaysHiddenBelowRevealThreshold() {
    let state = SessionSettingsOverpullState.hidden.tracking(topContentOffset: 60)

    #expect(state == .hidden)
}

@Test func sessionSettingsOverpullRevealsWhenOverpullClearsThreshold() {
    let state = SessionSettingsOverpullState.hidden.tracking(topContentOffset: 72)

    #expect(state == .pinned)
}

@Test func sessionSettingsOverpullStaysRevealedWhenSettlingShrinksOverpull() {
    // The reveal must latch so top-edge geometry settling cannot snap it back to
    // hidden mid-pull.
    let revealed = SessionSettingsOverpullState.hidden.tracking(topContentOffset: 80)
    #expect(revealed == .pinned)

    let afterSettling = revealed.tracking(topContentOffset: 20)
    #expect(afterSettling == .pinned)
}

@Test func pinnedSessionSettingsDismissesWhenScrollingIntoContent() {
    let state = SessionSettingsOverpullState.pinned.tracking(topContentOffset: -20)

    #expect(state == .hidden)
}

@Test func pinnedSessionSettingsDismissesAfterIdleDelay() {
    #expect(SessionSettingsOverpullState.pinned.dismissedAfterIdle() == .hidden)
}

@Test func sessionSettingsOverpullCountsOnlyDistanceBeyondScrolledContent() {
    let distance = SessionSettingsOverpullState.overpullDistance(
        startTopContentOffset: -70,
        translationHeight: 210
    )

    #expect(distance == 140)
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsBaseNameAndSetResults() {
    let exercise = Exercise(
        name: "2-3:1:0 Competition Squat",
        baseName: "Competition Squat",
        cadence: "2-3:1:0",
        coachNote: nil
    )
    let firstSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    firstSet.setLog = SetLog(weight: .pounds(185), reps: 8, rpe: 6)
    exercise.sets = [firstSet]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Competition Squat · 185×8")
}

@MainActor
@Test func exerciseSummaryRowPresentationAbbreviatesConsecutiveSameWeightSets() {
    let exercise = Exercise(name: "BB RDL", baseName: "BB RDL", cadence: nil, coachNote: nil)
    let firstSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    firstSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let secondSet = ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    secondSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let thirdSet = ExerciseSet(index: 2, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    thirdSet.setLog = SetLog(weight: .pounds(245), reps: 6, rpe: 7)
    exercise.sets = [firstSet, secondSet, thirdSet]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ BB RDL · 225×8 / ×8 / 245×6")
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsSkippedSetsAsSkip() {
    let exercise = Exercise(name: "BB RDL", baseName: "BB RDL", cadence: nil, coachNote: nil)
    let firstSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    firstSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let secondSet = ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    secondSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let thirdSet = ExerciseSet(index: 2, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .skipped)
    exercise.sets = [firstSet, secondSet, thirdSet]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ BB RDL · 225×8 / ×8 / skip")
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsRawLegacyLog() {
    let exercise = Exercise(
        name: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        cadence: nil,
        coachNote: nil,
        legacyLog: "25x12, 12"
    )
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged)
    ]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Standing Calve Raises · 25x12, 12")
}

@MainActor
@Test func exerciseSummaryRowPresentationPrefersStructuredLogsOverLegacyLog() {
    let exercise = Exercise(
        name: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        cadence: nil,
        coachNote: nil,
        legacyLog: "25x12, 12"
    )
    let set = ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged)
    set.setLog = SetLog(weight: .pounds(35), reps: 12, rpe: 9)
    exercise.sets = [set]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Standing Calve Raises · 35×12")
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsRawLegacyLogWhenSetLevelSkipExists() {
    let exercise = Exercise(
        name: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        cadence: nil,
        coachNote: nil,
        legacyLog: "25x12, 12"
    )
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .skipped)
    ]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Standing Calve Raises · 25x12, 12")
}

@MainActor
@Test func lastPerformedCardPresentationShowsLabelSetLogAndSource() {
    let entry = LastPerformedEntry(
        fullName: "DB Fly",
        baseName: "DB Fly",
        result: SetLog(weight: .pounds(25), reps: 12, rpe: 9),
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "W4 D3"
    )

    let presentation = LastPerformedCardPresentation(entry: entry)

    #expect(presentation.label == "Last Performed")
    #expect(presentation.resultText == "25x12@9")
    #expect(presentation.sourceText == "W4 D3")
}

@MainActor
@Test func lastPerformedCardPresentationShowsRawLegacyResultText() {
    let entry = LastPerformedEntry(
        fullName: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        resultText: "25x12, 12",
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "W4 D3"
    )

    let presentation = LastPerformedCardPresentation(entry: entry)

    #expect(presentation.resultText == "25x12, 12")
    #expect(presentation.sourceText == "W4 D3")
}

@MainActor
@Test func lastPerformedCardPresentationUsesIndexLookupForExercise() throws {
    let container = try activeSetPresentationContainer()
    let context = container.mainContext
    context.insert(
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(185), reps: 7, rpe: 6),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "W3 D1"
        )
    )
    try context.save()
    let exercise = Exercise(
        name: "2-3:1:0 BB RDL",
        baseName: "BB RDL",
        cadence: "2-3:1:0",
        coachNote: nil
    )

    let presentation = try #require(
        LastPerformedCardPresentation(
            exercise: exercise,
            lookup: LastPerformedLookupStore(context: context).snapshot
        )
    )

    #expect(presentation.resultText == "185x7@6")
    #expect(presentation.sourceText == "W3 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedCardPresentationIsNilWhenIndexHasNoEntry() throws {
    let container = try activeSetPresentationContainer()
    let exercise = Exercise(
        name: "Bench Press",
        baseName: "Bench Press",
        cadence: nil,
        coachNote: nil
    )

    let presentation = LastPerformedCardPresentation(
        exercise: exercise,
        lookup: LastPerformedLookupStore(context: container.mainContext).snapshot
    )

    #expect(presentation == nil)
    withExtendedLifetime(container) {}
}

@Test func lastPerformedCardPresentationCarriesTierThreeMatchedName() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "Standing Calve Raises",
            baseName: "Standing Calve Raises",
            resultText: "25x12",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])
    let exercise = Exercise(
        name: "Standing Calf Raise",
        baseName: "Standing Calf Raise",
        cadence: nil,
        coachNote: nil,
        order: 0
    )

    let presentation = LastPerformedCardPresentation(exercise: exercise, lookup: snapshot)
    #expect(presentation?.resultText == "25x12")
    #expect(presentation?.matchedName == "Standing Calve Raises")
}

@Test func lastPerformedCardPresentationHasNoMatchedNameForExactMatch() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            resultText: "205x5",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)

    let presentation = LastPerformedCardPresentation(exercise: exercise, lookup: snapshot)
    #expect(presentation?.matchedName == nil)
}
