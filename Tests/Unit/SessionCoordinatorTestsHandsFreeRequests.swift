import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func aSecondRequestWhileListeningDoesNothing() async throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    let slot = try fixture.card(in: session)
    let listening = Task { await fixture.coordinator.listenHandsFree(to: slot.set) }
    await fixture.clock.waitUntilSleeping(until: SetDictation.silenceWindow, orRecord: "The card never listened")
    let closings = fixture.entry.coverClosings

    fixture.entry.deliver(.dictateCurrentSet)
    fixture.coordinator.answerEntry()

    #expect(fixture.entry.pending == nil)
    #expect(fixture.entry.coverClosings == closings)
    #expect(!fixture.coordinator.startsHandsFree(slot))
    fixture.clock.advance(by: SetDictation.silenceWindow)
    _ = await listening.value
    #expect(fixture.ledger.entries.filter { $0 == .logged }.count == 1)
    #expect(fixture.navigation.currentSessionShows == 0)
}

@MainActor
@Test func aRequestWhileTheMicIsHeldDoesNothing() throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session, requested: false)
    let slot = try fixture.card(in: session)
    fixture.coordinator.startDictation(for: slot.set)
    #expect(fixture.dictation?.state.listeningSetID == firstBench)

    fixture.entry.deliver(.dictateCurrentSet)
    fixture.coordinator.answerEntry()

    #expect(fixture.entry.pending == nil)
    #expect(fixture.entry.coverClosings == 0)
    #expect(fixture.dictation?.state.listeningSetID == firstBench)
}

@MainActor
@Test func aRequestWhileTheCardHoldsASpokenSetMovesTheCardOnAndListensForTheNextSet() async throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    _ = await fixture.listenUntilQuiet(on: try fixture.card(in: session))
    #expect(try fixture.card(in: session).mode == .heldAfterSpokenWrite)

    fixture.entry.deliver(.dictateCurrentSet)
    fixture.coordinator.answerEntry()

    let next = try fixture.card(in: session)
    #expect(next.mode == .logging)
    #expect(SessionCoordinator.activeSetID(for: next.set) == secondBench)
    #expect(fixture.coordinator.startsHandsFree(next))
}

@MainActor
@Test func aRequestWhileTheCardReviewsALoggedSetClosesTheReviewAndListensForTheActiveSet() throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session, requested: false)
    let squat = try #require(session.exercises.first { $0.order == 0 }?.sets.first)
    fixture.coordinator.focus(on: squat)
    #expect(try fixture.card(in: session).mode == .reviewingLogged(showsSavedConfirmation: false))

    fixture.entry.deliver(.dictateCurrentSet)
    fixture.coordinator.answerEntry()

    let active = try fixture.card(in: session)
    #expect(active.mode == .logging)
    #expect(SessionCoordinator.activeSetID(for: active.set) == firstBench)
    #expect(fixture.coordinator.startsHandsFree(active))
    #expect(fixture.entry.coverClosings > 0)
}

@MainActor
@Test func aCardLeavingForAnotherSetLeavesThePressOfTheCardThatReplacedItRunning() async throws {
    let (current, currentSet) = makeSingleSetSession(dayNumber: 1)
    let (_, otherSessionsSet) = makeSingleSetSession(dayNumber: 3)
    let transcriber = HeldSetTranscriber(candidates: ["185 for 6 at 7"])
    let dictation = SetDictation(transcriber: transcriber)
    let coordinator = SessionCoordinator(wiring: .fixture(), dictation: dictation)
    coordinator.view(current)
    coordinator.startDictation(for: currentSet)

    await coordinator.cancelDictation(of: otherSessionsSet)

    #expect(dictation.state.listeningSetID == SessionCoordinator.activeSetID(for: currentSet))
    let cancelling = Task { await coordinator.cancelDictation(of: currentSet) }
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    await cancelling.value
    #expect(transcriber.wasCancelled)
    #expect(dictation.state == .idle)
}

@MainActor
@Test func aCardLeavingForAnotherSetOfTheSameSessionLeavesThePressRunning() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let bench = try #require(session.exercises.first { $0.order == 1 })
    coordinator.startDictation(for: try #require(bench.sets.first { $0.index == 0 }))

    await coordinator.cancelDictation(of: try #require(bench.sets.first { $0.index == 1 }))

    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .listening(caption: "Listening"))
}

@MainActor
@Test func aRequestForAnActiveSetThatIsNotPendingEndsThere() throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session, requested: false)
    let skipped = try fixture.card(in: session).set
    fixture.coordinator.skip(skipped)
    fixture.coordinator.focus(on: skipped)

    fixture.entry.deliver(.dictateCurrentSet)
    fixture.coordinator.answerEntry()

    #expect(fixture.entry.pending == nil)
    #expect(fixture.entry.coverClosings == 0)
}

@MainActor
@Test func onlyTheCardOfTheSetARequestWaitsForCanTakeIt() async throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    let other = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 1 })

    #expect(await fixture.coordinator.listenHandsFree(to: other) == nil)
    #expect(fixture.entry.pending == .dictateCurrentSet)
}
