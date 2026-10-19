import Foundation
import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)

private func outcome(of candidates: [String], in context: SpokenSetContext = squat) -> SetDictation.Outcome {
    SetDictation.decision(of: Hearing(live: .transcripts(candidates), recording: nil), in: context).outcome
}

@Test func aCompleteSetLogReadFromTheTopTranscriptIsLogged() {
    #expect(outcome(of: ["135 for 4 at RPE 9"]) == .logged(SetLog(weight: .pounds(135), reps: 4, rpe: .nine), heard: "135 for 4 at RPE 9"))
}

@Test func aSkipReadFromTheTopTranscriptIsSkipped() {
    #expect(outcome(of: ["skip"]) == .skipped(heard: "skip"))
}

@Test func sameAgainLogsTheEarlierSetLog() {
    let previous = SetLog(weight: .pounds(180), reps: 5, rpe: .eightPointFive)
    let secondSquat = SpokenSetContext(draft: squat.draft, previous: previous)

    #expect(outcome(of: ["same again"], in: secondSquat) == .logged(previous, heard: "same again"))
}

@Test func aValueTheTopTranscriptCutOffThatEveryAlternativeSettlesIsLogged() {
    #expect(
        outcome(of: ["135 for 4 and 9", "135 for 4 at 9"])
            == .logged(SetLog(weight: .pounds(135), reps: 4, rpe: .nine), heard: "135 for 4 and 9")
    )
    #expect(
        outcome(of: ["135 for 4 and 9", "135 for 4 at 9", "135 for 4 at 8"])
            == .filled(SetLogDraft(weight: .pounds(135), reps: 4, rpe: nil), heard: "135 for 4 and 9")
    )
}

@Test func aSetLogReadOnlyFromAnAlternativeFillsTheCardAndWritesNothing() {
    let filled = outcome(of: ["13549", "135 for 4 at 9"])

    #expect(filled == .filled(SetLogDraft(weight: .pounds(135), reps: 4, rpe: .nine), heard: "13549"))
}

@Test func aSetNoLifterLogsDefersToTheAlternativesAndWritesNothing() {
    #expect(
        outcome(of: ["135 for 101 at 8", "135 for 10 at 8"])
            == .filled(SetLogDraft(weight: .pounds(135), reps: 10, rpe: .eight), heard: "135 for 101 at 8")
    )
    #expect(outcome(of: ["135 for 101 at 8"]) == .rejected(.spokenSet(.implausible(.reps)), heard: "135 for 101 at 8"))
    #expect(outcome(of: ["12.47 for 3", "12.47 for 3."]) == .rejected(.spokenSet(.implausible(.weight)), heard: "12.47 for 3"))
}

@Test func aSkipReadOnlyFromAnAlternativeWritesNothing() {
    #expect(outcome(of: ["skit", "skip it"]) == .rejected(.spokenSet(.ambiguous), heard: "skit"))
}

@Test func valuesStillMissingOneFillTheCardWithTheMissingFieldMarked() {
    let fresh = SpokenSetContext(draft: SetLogDraft(weight: nil, reps: 5, rpe: .seven), previous: nil)

    let filled = outcome(of: ["RPE 9"], in: fresh)

    #expect(filled == .filled(SetLogDraft(weight: nil, reps: 5, rpe: .nine), heard: "RPE 9"))
    guard case .filled(let values, _) = filled else { return }
    #expect(values.missingFields == [.weight])
}

/// The card pre-fills 185 lb, so a reading of 135 reps with no weight would log 185x135@9.
@Test func aRepCountTheRecognizerDroppedWritesNothingOnACardThatPreFillsAWeight() {
    #expect(outcome(of: ["135, a representative, RP9"]) == .rejected(.spokenSet(.unrecognized), heard: "135, a representative, RP9"))
    #expect(
        outcome(of: ["135, 8 reps, RPE 9"]) == .logged(SetLog(weight: .pounds(135), reps: 8, rpe: .nine), heard: "135, 8 reps, RPE 9")
    )
}

@Test func aRejectedTranscriptWritesNothingAndKeepsWhatWasHeard() {
    #expect(outcome(of: ["100 kilos for 5"]) == .rejected(.spokenSet(.kilograms), heard: "100 kilos for 5"))
}

@Test func sameAgainWithNothingEarlierIsRejected() {
    #expect(outcome(of: ["same again"]) == .rejected(.spokenSet(.nothingToRepeat), heard: "same again"))
}

@Test func noTranscriptIsNothingHeard() {
    #expect(outcome(of: []) == .rejected(.spokenSet(.nothingHeard), heard: ""))
}

@MainActor
@Test func aSetResolvesAgainstItsCardsPrefillAndTheNearestEarlierSetLog() throws {
    let exercise = makeExercise(setStates: [.logged, .logged, .pending])
    let thirdSet = try #require(exercise.sets.first { $0.index == 2 })

    let context = SpokenSetContext(for: thirdSet, history: .empty)

    #expect(context.previous == SetLog(weight: .pounds(195), reps: 5, rpe: .eight))
    #expect(context.draft.reps == 5)
    #expect(context.draft.rpe == .nine)
}

@MainActor
@Test func dictationPreparesThenListensWithWhatIsHeardThenFinishesWithTheOutcome() async {
    let transcriber = HeldSetTranscriber(candidates: ["135 for 4 at 9"])
    let dictation = SetDictation(transcriber: transcriber)

    dictation.start(for: firstSet)
    #expect(dictation.state == .preparing(firstSet))

    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    let finishing = Task { await dictation.finish(for: firstSet, in: squat) }
    await transcriber.finishing.waitUntilHeld(orRecord: "The transcriber never finished")
    #expect(dictation.state == .listening(firstSet, heard: "135 for 4 at 9"))

    transcriber.finishing.release()
    let logged = SetDictation.Outcome.logged(SetLog(weight: .pounds(135), reps: 4, rpe: .nine), heard: "135 for 4 at 9")
    #expect(await finishing.value == logged)
    #expect(dictation.state == .finished(firstSet, logged))
}

@MainActor
@Test func releasingBeforeTheTranscriberStartsStillFinishesWhatItHeard() async {
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]))

    dictation.start(for: firstSet)
    let skipped = await dictation.finish(for: firstSet, in: squat)

    #expect(skipped == .skipped(heard: "skip"))
}

@MainActor
@Test(
    "A transcriber that fails to start is rejected with nothing heard",
    arguments: [SetTranscriberError.microphoneDenied, .unavailable, .failed]
)
func aTranscriberThatFailsToStartIsRejected(error: SetTranscriberError) async {
    let dictation = SetDictation(transcriber: FailingSetTranscriber(failsToStart: error))

    dictation.start(for: firstSet)
    let rejected = await dictation.finish(for: firstSet, in: squat)

    #expect(rejected == .rejected(.transcriber(error), heard: ""))
    #expect(dictation.state == .finished(firstSet, .rejected(.transcriber(error), heard: "")))
}

@MainActor
@Test(
    "A transcriber that fails to finish is rejected with what it had heard",
    arguments: [SetTranscriberError.nothingHeard, .failed]
)
func aTranscriberThatFailsToFinishKeepsWhatItHadHeard(error: SetTranscriberError) async {
    let dictation = SetDictation(transcriber: FailingSetTranscriber(hearing: "135 for", failsToFinish: error))

    dictation.start(for: firstSet)
    let rejected = await dictation.finish(for: firstSet, in: squat)

    #expect(rejected == .rejected(.transcriber(error), heard: "135 for"))
}

@MainActor
@Test func finishingAnotherSetThanTheOneListenedForDoesNothing() async {
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]))
    let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)

    dictation.start(for: firstSet)
    let finished = await dictation.finish(for: secondSet, in: squat)

    #expect(finished == nil)
    #expect(dictation.state == .preparing(firstSet))
}

@MainActor
@Test func startingWhileListeningKeepsTheFirstSet() async {
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]))

    dictation.start(for: firstSet)
    dictation.start(for: ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(dictation.state == .preparing(firstSet))
}

@MainActor
@Test func cancellingStopsTheTranscriberAndForgetsTheSet() async {
    let transcriber = HeldSetTranscriber(candidates: ["skip"])
    let dictation = SetDictation(transcriber: transcriber)

    dictation.start(for: firstSet)
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    await dictation.cancel()

    #expect(transcriber.wasCancelled)
    #expect(dictation.state == .idle)
    #expect(await dictation.finish(for: firstSet, in: squat) == nil)
}

@MainActor
@Test func dismissingAFinishedOutcomeReturnsToIdleAndAllowsAnotherStart() async {
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]))
    dictation.start(for: firstSet)
    _ = await dictation.finish(for: firstSet, in: squat)

    dictation.dismiss()
    #expect(dictation.state == .idle)
    dictation.start(for: firstSet)
    #expect(dictation.state == .preparing(firstSet))
}

@MainActor
@Test func aFinishedOutcomeGivesWayToTheNextStart() async {
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]))
    dictation.start(for: firstSet)
    _ = await dictation.finish(for: firstSet, in: squat)

    dictation.start(for: firstSet)

    #expect(dictation.state == .preparing(firstSet))
}

@MainActor
private final class FailingSetTranscriber: SetTranscriber {
    private let heard: String
    private let startFailure: SetTranscriberError?
    private let finishFailure: SetTranscriberError?

    init(failsToStart error: SetTranscriberError) {
        (heard, startFailure, finishFailure) = ("", error, nil)
    }

    init(hearing heard: String, failsToFinish error: SetTranscriberError) {
        (self.heard, startFailure, finishFailure) = (heard, nil, error)
    }

    func start(hearing: @escaping @MainActor (String) -> Void, recording _: DictationRecorder) async throws(SetTranscriberError) {
        if let startFailure { throw startFailure }
        hearing(heard)
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        if let finishFailure { throw finishFailure }
        return [heard]
    }

    func cancel() async {}
}

@Test(
    "The card's caption for a rejected press says what was heard, or why nothing was, and asks again for a Set no lifter logs",
    arguments: [
        (SetDictation.Rejection.spokenSet(.kilograms), "100 kilos for 5", "“100 kilos for 5”"),
        (.spokenSet(.implausible(.reps)), "180 for 546 at 8", "“180 for 546 at 8”, say it again"),
        (.spokenSet(.nothingHeard), "", "Nothing heard"),
        (.transcriber(.nothingHeard), "", "Nothing heard"),
        (.transcriber(.failed), "135 for", "“135 for”"),
        (.transcriber(.failed), "", "Nothing heard"),
        (.transcriber(.microphoneDenied), "", "Microphone is off in Settings"),
        (.transcriber(.unavailable), "", "Speech isn’t available")
    ]
)
func theCardsCaptionForARejectedPress(rejection: SetDictation.Rejection, heard: String, caption: String) {
    let state = SetDictation.State.finished(firstSet, .rejected(rejection, heard: heard))

    #expect(SetCardDictation(state, for: firstSet) == .rejected(caption: caption))
}

@Test func theCardShowsThePressOnlyForItsOwnSet() {
    let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)

    #expect(SetCardDictation(.listening(firstSet, heard: "135 for"), for: firstSet) == .listening(caption: "135 for"))
    #expect(SetCardDictation(.listening(firstSet, heard: "135 for"), for: secondSet) == .ready)
}

@Test func theCapsuleCaptionsAPressInFlightOrRejectedAndTheMicShowsItIsListening() {
    let cases: [(SetCardDictation, String?, Bool)] = [
        (.ready, nil, false),
        (.listening(caption: "135 for"), "135 for", true),
        (.rejected(caption: "Nothing heard"), "Nothing heard", false),
        (.filled(SetLogDraft(weight: nil, reps: 4, rpe: .nine)), nil, false)
    ]

    for (dictation, caption, isListening) in cases {
        #expect(dictation.caption == caption)
        #expect(dictation.isListening == isListening)
    }
}

@Test func aPressFeelsLikeTheTapItStandsInForAndAnythingUnwrittenWarns() {
    let logged = SetDictation.Outcome.logged(SetLog(weight: .pounds(135), reps: 4, rpe: .nine), heard: "135 for 4 at 9")
    let filled = SetDictation.Outcome.filled(SetLogDraft(weight: nil, reps: 4, rpe: .nine), heard: "for 4 at 9")

    #expect(SetDictation.startHaptic == .input(Theme.Haptics.stepperTick))
    #expect(logged.haptic == .input(Theme.Haptics.logTap))
    #expect(SetDictation.Outcome.skipped(heard: "skip").haptic == .input(Theme.Haptics.skipDud))
    #expect(filled.haptic == .warning)
    #expect(SetDictation.Outcome.rejected(.spokenSet(.kilograms), heard: "100 kilos").haptic == .warning)
}
