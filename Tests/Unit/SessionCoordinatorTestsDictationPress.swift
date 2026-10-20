import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func aPressBegunBeforeTheSessionChangedWritesNothingToTheNewOne() async throws {
    let (first, firstSet) = makeSingleSetSession(dayNumber: 1)
    let (second, secondSet) = makeSingleSetSession(dayNumber: 2)
    let (coordinator, ledger, _) = makeDictationCoordinator(session: first, saying: ["185 for 6 at 7"])
    coordinator.startDictation(for: firstSet)

    coordinator.view(second)
    let outcome = await coordinator.finishDictation(of: firstSet)

    #expect(outcome == nil)
    #expect(ledger.entries == [.liveActivityReconciled])
    #expect(secondSet.isPending)
    #expect(coordinator.cardDictation(for: try card(coordinator, in: second)) == .ready)
}

@MainActor
@Test func aReleaseOnACardNowShowingAnotherSetWritesNothingAndFreesTheMic() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let pressed = try card(coordinator, in: session).set
    let next = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 1 })
    coordinator.startDictation(for: pressed)
    let entriesBeforeTheRelease = ledger.entries.count

    let outcome = await coordinator.finishDictation(of: next)

    #expect(outcome == nil)
    #expect(ledger.entries.count == entriesBeforeTheRelease)
    #expect(pressed.isPending && next.isPending)
    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .ready)
}

@MainActor
@Test func aSetLoggedByTapWhileItsTranscriptCameInIsWrittenOnceAndThePressLetGo() async throws {
    let session = makeCoordinatorSession()
    let transcriber = HeldSetTranscriber(candidates: ["185 for 6 at 7"])
    let dictation = SetDictation(transcriber: transcriber)
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, dictation: dictation)
    let set = try card(coordinator, in: session).set
    coordinator.startDictation(for: set)
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    let releasing = Task {
        await coordinator.finishDictation(of: set)
    }
    await transcriber.finishing.waitUntilHeld(orRecord: "The transcriber never finished")

    let tapped = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
    coordinator.log(set, as: tapped)
    let entriesAfterTheTap = ledger.entries.count
    transcriber.finishing.release()

    #expect(await releasing.value == nil)
    #expect(ledger.entries.count == entriesAfterTheTap)
    #expect(set.setLog == tapped)
    #expect(dictation.state == .idle)
}

@MainActor
@Test func aSessionChangedWhileTheTranscriptCameInGetsNothingWrittenAndThePressLetGo() async throws {
    let (first, firstSet) = makeSingleSetSession(dayNumber: 1)
    let (second, secondSet) = makeSingleSetSession(dayNumber: 2)
    let transcriber = HeldSetTranscriber(candidates: ["185 for 6 at 7"])
    let dictation = SetDictation(transcriber: transcriber)
    let (coordinator, ledger, _) = makeDictationCoordinator(session: first, dictation: dictation)
    coordinator.startDictation(for: firstSet)
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    let releasing = Task {
        await coordinator.finishDictation(of: firstSet)
    }
    await transcriber.finishing.waitUntilHeld(orRecord: "The transcriber never finished")

    coordinator.view(second)
    transcriber.finishing.release()

    #expect(await releasing.value == nil)
    #expect(ledger.entries == [.liveActivityReconciled])
    #expect(firstSet.isPending && secondSet.isPending)
    #expect(dictation.state == .idle)
}

/// Presses the mic on `set`'s card and lets go, returning while the transcript is still coming in.
@MainActor
func letGoOfTheMic(
    on set: ExerciseSet,
    of coordinator: SessionCoordinator,
    hearing transcriber: HeldSetTranscriber
) async -> Task<SetDictation.Outcome?, Never> {
    coordinator.startDictation(for: set)
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    let releasing = Task {
        await coordinator.finishDictation(of: set)
    }
    await transcriber.finishing.waitUntilHeld(orRecord: "The transcriber never finished")
    return releasing
}

@MainActor
@Test func aSpokenSetLogLandingAfterTheAthleteMovedToAnotherSetLeavesTheCardThere() async throws {
    let session = makeCoordinatorSession()
    let transcriber = HeldSetTranscriber(candidates: ["185 for 6 at 7"])
    let (coordinator, _, clock) = makeDictationCoordinator(session: session, dictation: SetDictation(transcriber: transcriber))
    let released = try card(coordinator, in: session).set
    let row = try #require(session.exercises.first { $0.order == 2 }?.sets.first)
    let releasing = await letGoOfTheMic(on: released, of: coordinator, hearing: transcriber)

    coordinator.focus(on: row)
    transcriber.finishing.release()

    #expect(await releasing.value == .logged(SetLog(weight: .pounds(185), reps: 6, rpe: .seven), heard: "185 for 6 at 7"))
    #expect(released.state == .logged)
    let shown = try #require(exerciseStage(coordinator, in: session)?.card)
    #expect(shown.set === row)
    #expect(shown.mode == .logging)
    #expect(clock.sleptDurations.isEmpty)
}

@MainActor
@Test func aSpokenSetLogLandingUnderAReviewKeepsTheReviewAndMovesTheActiveSetOn() async throws {
    let session = makeCoordinatorSession()
    let transcriber = HeldSetTranscriber(candidates: ["185 for 6 at 7"])
    let (coordinator, _, clock) = makeDictationCoordinator(session: session, dictation: SetDictation(transcriber: transcriber))
    let released = try card(coordinator, in: session).set
    let squat = try #require(session.exercises.first { $0.order == 0 }?.sets.first)
    let releasing = await letGoOfTheMic(on: released, of: coordinator, hearing: transcriber)

    coordinator.focus(on: squat)
    transcriber.finishing.release()

    #expect(await releasing.value == .logged(SetLog(weight: .pounds(185), reps: 6, rpe: .seven), heard: "185 for 6 at 7"))
    #expect(released.state == .logged)
    let reviewed = try #require(exerciseStage(coordinator, in: session)?.card)
    #expect(reviewed.set === squat)
    #expect(reviewed.mode == .reviewingLogged(showsSavedConfirmation: false))
    #expect(clock.sleptDurations.isEmpty)
    coordinator.focus(on: squat)
    #expect(coordinator.activeSetID == secondBench)
    #expect(try card(coordinator, in: session).mode == .logging)
}

@MainActor
@Test func theMicIsOnTheCardOnlyForAPendingSetBeingLogged() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let squat = try #require(session.exercises.first { $0.order == 0 }?.sets.first)
    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .ready)

    _ = try await sayIntoTheCard(coordinator, in: session)
    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == nil)

    coordinator.focus(on: squat)
    #expect(try card(coordinator, in: session).mode == .reviewingLogged(showsSavedConfirmation: false))
    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == nil)

    let withoutTranscriber = SessionCoordinator(session: session, wiring: .fixture())
    #expect(withoutTranscriber.cardDictation(for: try card(withoutTranscriber, in: session)) == nil)
}

@MainActor
@Test func theCardShowsWhatIsHeardWhileListening() throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let slot = try card(coordinator, in: session)

    coordinator.startDictation(for: slot.set)

    #expect(coordinator.cardDictation(for: slot) == .listening(caption: "Listening"))
}
