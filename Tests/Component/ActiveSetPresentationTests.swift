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

@Test func holdToSkipPolicyDefaultsToTheIdleSetHold() {
    let policy = HoldToSkipPolicy()
    #expect(policy.holdDuration == 0.85)
    #expect(policy.revealDelay == 0.25)
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

    #expect(presentation.skipOpacity == 0)
    #expect(presentation.tone == .incomplete)
    #expect(presentation.accessibilityHint == "Double tap to show what is missing. Press and hold to skip this Set.")
}

@Test func holdToSkipButtonPresentationShowsSkippedFeedbackOnlyDuringHoldProgress() {
    let presentation = HoldToSkipButtonPresentation(progress: 0.65, logTitle: "Log", canLog: false)

    #expect(abs(presentation.skipOpacity - 0.65) < 0.001)
    #expect(presentation.accessibilityLabel == "Skipped")
}

@MainActor
@Test func setRowPresentationShowsLoggedSetLog() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
    set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "185x5@8")
}

@MainActor
@Test func setRowPresentationShowsSkippedSetAsSkip() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "skip")
}

@MainActor
@Test func setRowPresentationShowsPendingSetAsPrescription() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "5 · RPE 8")
}

@MainActor
struct SetCardPresentationTests {
    @MainActor
    private struct CardCase {
        let mode: SetCardMode
        let set: ExerciseSet
        let makeIncomplete: (inout SmartValuePillsForm) -> Void
        let makeValid: (inout SmartValuePillsForm) -> Void

        var drafts: [SmartValuePillsForm] {
            let untouched = SmartValuePillsForm(set: set, suggestion: .noSuggestion)
            var incomplete = untouched
            makeIncomplete(&incomplete)
            var valid = untouched
            makeValid(&valid)
            return [untouched, incomplete, valid]
        }

        var actionRows: [SetCardPresentation.ActionRow] {
            let presentation = SetCardPresentation(mode: mode, set: set)
            return drafts.map(presentation.actionRow(for:))
        }
    }

    private static func structuredSet(_ state: SetState) -> ExerciseSet {
        let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: state)
        if state == .logged {
            set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
        }
        return set
    }

    private static func unstructuredLoggedSet() -> ExerciseSet {
        let set = ExerciseSet(index: 1, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .logged)
        set.unstructuredSetLog = "BW and vest for 12"
        return set
    }

    private let cases: KeyValuePairs<String, CardCase> = [
        "logging a pending Set": CardCase(
            mode: .logging,
            set: structuredSet(.pending),
            makeIncomplete: { $0.repsText = "" },
            makeValid: { $0.weightText = "185" }
        ),
        "logging a skipped Set": CardCase(
            mode: .logging,
            set: structuredSet(.skipped),
            makeIncomplete: { $0.repsText = "" },
            makeValid: { $0.weightText = "185" }
        ),
        "logging a logged Set": CardCase(
            mode: .logging,
            set: structuredSet(.logged),
            makeIncomplete: { $0.rpeText = "" },
            makeValid: { $0.stepWeight(.up) }
        ),
        "reviewing a structured Set Log": CardCase(
            mode: .reviewingLogged,
            set: structuredSet(.logged),
            makeIncomplete: { $0.rpeText = "" },
            makeValid: { $0.stepWeight(.up) }
        ),
        "reviewing an Unstructured Set Log": CardCase(
            mode: .reviewingLogged,
            set: unstructuredLoggedSet(),
            makeIncomplete: { $0.repsText = "12" },
            makeValid: {
                $0.weightText = "BW"
                $0.repsText = "12"
                $0.rpeText = "8"
            }
        )
    ]

    @Test func eachCaseDraftsAnUntouchedThenAChangedIncompleteThenAChangedValidSetLog() {
        let states = Dictionary(
            uniqueKeysWithValues: cases.map { name, card in
                (name, card.drafts.map { [$0.hasChanges, $0.canLog] })
            }
        )

        #expect(
            states == [
                "logging a pending Set": [[false, false], [true, false], [true, true]],
                "logging a skipped Set": [[false, false], [true, false], [true, true]],
                "logging a logged Set": [[false, true], [true, false], [true, true]],
                "reviewing a structured Set Log": [[false, true], [true, false], [true, true]],
                "reviewing an Unstructured Set Log": [[false, false], [true, false], [true, true]]
            ]
        )
    }

    @Test func eachCardModeDrawsItsActionRowForAnUntouchedAnIncompleteAndAValidDraft() {
        let rows = Dictionary(uniqueKeysWithValues: cases.map { ($0.key, $0.value.actionRows) })

        #expect(
            rows == [
                "logging a pending Set": [.log, .log, .log],
                "logging a skipped Set": [.skipped, .skipped, .skipped],
                "logging a logged Set": [.log, .log, .log],
                "reviewing a structured Set Log": [
                    .logged(line: "185x5@8"), .incompleteDraft, .logged(line: "185x5@8")
                ],
                "reviewing an Unstructured Set Log": [
                    .logged(line: "BW and vest for 12"),
                    .logged(line: "BW and vest for 12"),
                    .logged(line: "BW and vest for 12")
                ]
            ]
        )
    }

    @Test func onlyLoggingASetAlreadyDoneOffersClearAndOnlyAReviewCommitsOnDisappear() {
        let flags = Dictionary(
            uniqueKeysWithValues: cases.map { name, card in
                let presentation = SetCardPresentation(mode: card.mode, set: card.set)
                return (name, [presentation.showsClearMenu, presentation.commitsChangesOnDisappear])
            }
        )

        #expect(
            flags == [
                "logging a pending Set": [false, false],
                "logging a skipped Set": [true, false],
                "logging a logged Set": [true, false],
                "reviewing a structured Set Log": [false, true],
                "reviewing an Unstructured Set Log": [false, true]
            ]
        )
    }
}

@Test func onlyTheFocusMorphYieldsToReduceMotion() {
    let motions: [SessionMotion] = [.momentumFlow, .skipFadeUp, .focusMorph]

    #expect(motions.map { $0.runs(reducingMotion: false) } == [true, true, true])
    #expect(motions.map { $0.runs(reducingMotion: true) } == [true, true, false])
}

@Test func eachSessionMotionRunsItsDesignedCurveAndDuration() {
    #expect(SessionMotion.momentumFlow.animation == .easeInOut(duration: 0.65))
    #expect(SessionMotion.skipFadeUp.animation == .easeOut(duration: 0.45))
    #expect(SessionMotion.focusMorph.animation == .easeInOut(duration: 0.28))
}

@MainActor
@Test func sessionProgressHeaderPresentationShowsCompactLocationAndRemainingCount() {
    let block = Block(tabName: "Block 27")
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

    let presentation = SessionProgressHeaderPresentation(session: session, block: block)

    #expect(presentation.runlineText == "Block 27 · Week 2 · Day 3")
    #expect(presentation.completedSetCount == 2)
    #expect(presentation.totalSetCount == 3)
    #expect(presentation.remainingText == "1 Set left")
    #expect(presentation.locationActionAccessibilityLabel == "Open Block Overview for Week 2, Day 3")
    #expect(presentation.progressAccessibilityValue == "Block 27 · Week 2 · Day 3, 1 Set left")
}

@MainActor
@Test func sessionProgressHeaderRunlineDropsTheBlockPrefixWhenNoBlockIsKnown() {
    let week = Week(number: 4)
    let session = Session(dayNumber: 1, date: nil)
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [exercise]
    week.sessions = [session]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.runlineText == "Week 4 · Day 1")
    #expect(presentation.remainingText == "2 Sets left")
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
@Test func lastPerformedCardPresentationShowsLabelSetLogAndSource() {
    let entry = LastPerformedEntry(
        fullName: "DB Fly",
        baseName: "DB Fly",
        resultText: "25x12@9",
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "W4 D3"
    )

    let presentation = LastPerformedCardPresentation(entry: entry)

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
            resultText: "185x7@6",
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
