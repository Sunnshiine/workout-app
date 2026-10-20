import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
func makeDictationCoordinator(
    session: Session,
    saying candidates: [String],
    restTimer: RestTimer = RestTimer(
        clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0)),
        expiryScheduler: HeldRestExpiry()
    )
) -> (coordinator: SessionCoordinator, ledger: SessionVerbLedger, clock: ManualSessionTransitionClock) {
    makeDictationCoordinator(
        session: session,
        dictation: SetDictation(transcriber: CannedSetTranscriber(candidates: candidates)),
        restTimer: restTimer
    )
}

@MainActor
func makeDictationCoordinator(
    session: Session,
    dictation: SetDictation,
    restTimer: RestTimer = RestTimer(
        clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0)),
        expiryScheduler: HeldRestExpiry()
    )
) -> (coordinator: SessionCoordinator, ledger: SessionVerbLedger, clock: ManualSessionTransitionClock) {
    let ledger = SessionVerbLedger()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: ledger,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: ledger,
            restTimer: restTimer,
            restDurations: restDurations(standard: 210),
            liveActivity: ledger,
            motion: ledger
        ),
        transitionClock: clock,
        dictation: dictation
    )
    ledger.coordinator = coordinator
    return (coordinator, ledger, clock)
}

@MainActor
func card(_ coordinator: SessionCoordinator, in session: Session) throws -> SetCardSlot {
    try #require(exerciseStage(coordinator, in: session)?.card)
}

@MainActor
func sayIntoTheCard(_ coordinator: SessionCoordinator, in session: Session) async throws -> SetDictation.Outcome? {
    let set = try card(coordinator, in: session).set
    coordinator.startDictation(for: set)
    return await coordinator.finishDictation(of: set, resolvingAgainst: SpokenSetContext(for: set, history: .empty).draft)
}

let firstBench = ActiveSetID(exerciseOrder: 1, setIndex: 0)
let secondBench = ActiveSetID(exerciseOrder: 1, setIndex: 1)

@MainActor
@Test func aSpokenSetLogTakesTheLogTapsPathOnceThenHoldsTheLoggedSetOnTheCard() async throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let restTimer = RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000)))
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"], restTimer: restTimer)

    let outcome = try await sayIntoTheCard(coordinator, in: session)

    let logged = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    #expect(outcome == .logged(logged, heard: "185 for 6 at 7"))
    #expect(
        ledger.entries == [
            .began(.momentumFlow, focus: firstBench),
            .logged,
            .liveActivityStarted,
            .liveActivityReconciled,
            .ended(focus: secondBench),
            .flushRequested
        ]
    )
    #expect(restTimer.isRunning)
    let held = try card(coordinator, in: session)
    #expect(held.mode == .heldAfterSpokenWrite)
    #expect(held.set.setLog == logged)
    #expect(held.cardIdentity == "stage-held-1-0")
}

@MainActor
@Test func aSpokenSetFillsWhatItLeavesOutFromWhatTheCardShows() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["for 5 at 8"])
    let set = try card(coordinator, in: session).set
    coordinator.startDictation(for: set)

    let outcome = await coordinator.finishDictation(of: set, resolvingAgainst: SetLogDraft(weight: .pounds(190), reps: 3, rpe: .seven))

    let logged = SetLog(weight: .pounds(190), reps: 5, rpe: .eight)
    #expect(outcome == .logged(logged, heard: "for 5 at 8"))
    #expect(set.setLog == logged)
}

@MainActor
@Test func theHoldEndsAfterFourSecondsAndTheCardMovesOnInsideAMomentumFlow() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)
    let entriesBeforeTheHoldEnds = ledger.entries.count

    await clock.waitForSleep()
    #expect(clock.sleptDurations == [.seconds(4)])
    await clock.advance()

    let next = try card(coordinator, in: session)
    #expect(next.mode == .logging)
    #expect(SessionCoordinator.activeSetID(for: next.set) == secondBench)
    #expect(ledger.entries.dropFirst(entriesBeforeTheHoldEnds) == [.began(.momentumFlow, focus: secondBench), .ended(focus: secondBench)])
}

@MainActor
@Test func theHoldOfAnExercisesLastSetKeepsThatExerciseOnStageUntilItEnds() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let bench = try #require(session.exercises.first { $0.order == 1 })
    coordinator.log(try #require(bench.sets.first { $0.index == 0 }), as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    coordinator.focus(on: try #require(bench.sets.first { $0.index == 1 }))

    _ = try await sayIntoTheCard(coordinator, in: session)

    #expect(exerciseStage(coordinator, in: session)?.exercise === bench)
    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
    await clock.waitForSleep()
    await clock.advance()
    #expect(exerciseStage(coordinator, in: session)?.exercise.order == 2)
}

@MainActor
@Test func theHoldOfTheSessionsLastSetGivesWayToTheCompletionStage() async throws {
    let (session, _) = makeSingleSetSession(dayNumber: 1)
    let (coordinator, _, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])

    _ = try await sayIntoTheCard(coordinator, in: session)

    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
    await clock.waitForSleep()
    await clock.advance()
    guard case .complete = coordinator.stage(in: session, lookup: .empty).focus else {
        Issue.record("The stage did not complete once the hold ended")
        return
    }
}

@MainActor
@Test func aSpokenSkipTakesTheSkipPathThenHoldsTheSkippedSet() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["skip"])

    let outcome = try await sayIntoTheCard(coordinator, in: session)

    #expect(outcome == .skipped(heard: "skip"))
    #expect(
        ledger.entries == [
            .began(.skipFadeUp, focus: firstBench), .skipped, .liveActivityReconciled, .ended(focus: secondBench), .flushRequested
        ]
    )
    let held = try card(coordinator, in: session)
    #expect(held.mode == .heldAfterSpokenWrite)
    #expect(held.set.state == .skipped)
}

@MainActor
@Test(arguments: ["185 for 6 at 7", "skip"])
func aHeldSetTakesNoWriteFromItsCard(saying transcript: String) async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: [transcript])
    _ = try await sayIntoTheCard(coordinator, in: session)
    let held = try card(coordinator, in: session)
    let written = (held.set.state, held.set.setLog)
    let entriesWhileHeld = ledger.entries

    coordinator.log(SetLog(weight: .pounds(190), reps: 6, rpe: .eight), for: held)
    coordinator.skip(for: held)

    #expect(ledger.entries == entriesWhileHeld)
    #expect(held.set.state == written.0)
    #expect(held.set.setLog == written.1)
    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
}

@MainActor
@Test func clearingTheHeldSetUndoesTheWriteAndPutsItsCardBack() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)

    coordinator.deleteLog(for: try card(coordinator, in: session).set)

    #expect(ledger.entries.filter { $0 == .deleted }.count == 1)
    let cleared = try card(coordinator, in: session)
    #expect(cleared.mode == .logging)
    #expect(cleared.set.isPending)
    #expect(SessionCoordinator.activeSetID(for: cleared.set) == firstBench)
    let motionsAfterTheClear = ledger.motions
    await clock.waitForSleep()
    await clock.advance()
    #expect(SessionCoordinator.activeSetID(for: try card(coordinator, in: session).set) == firstBench)
    #expect(ledger.motions == motionsAfterTheClear)
}

@MainActor
@Test func touchingTheHeldCardMovesOnAtOnceAndTheHoldsEndChangesNothing() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)

    coordinator.endSpokenWriteHold()

    #expect(SessionCoordinator.activeSetID(for: try card(coordinator, in: session).set) == secondBench)
    #expect(ledger.motions == [.momentumFlow, .momentumFlow])
    await clock.waitForSleep()
    await clock.advance()
    #expect(ledger.motions == [.momentumFlow, .momentumFlow])
}

@MainActor
@Test func theHeldSetsOpenClearMenuKeepsItOnTheCardUntilTheMenuCloses() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)

    coordinator.suspendSpokenWriteHold()
    await clock.waitForSleep()
    await clock.advance()

    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
    #expect(ledger.motions == [.momentumFlow])

    coordinator.endSpokenWriteHold()

    let next = try card(coordinator, in: session)
    #expect(next.mode == .logging)
    #expect(SessionCoordinator.activeSetID(for: next.set) == secondBench)
    #expect(ledger.motions == [.momentumFlow, .momentumFlow])
}

@MainActor
@Test func aClearFromTheHeldSetsOpenMenuUndoesTheWriteAndTheMenuClosingLeavesIt() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)
    coordinator.suspendSpokenWriteHold()

    coordinator.deleteLog(for: try card(coordinator, in: session).set)
    let motionsAfterTheClear = ledger.motions
    coordinator.endSpokenWriteHold()
    await clock.waitForSleep()
    await clock.advance()

    let cleared = try card(coordinator, in: session)
    #expect(cleared.mode == .logging)
    #expect(cleared.set.isPending)
    #expect(SessionCoordinator.activeSetID(for: cleared.set) == firstBench)
    #expect(ledger.motions == motionsAfterTheClear)
}

@MainActor
@Test func aClearLandingAfterTheHeldSetsMenuClosedStillUndoesTheWriteAndBringsItsSetBack() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let held = try card(coordinator, in: session).set
    _ = try await sayIntoTheCard(coordinator, in: session)
    coordinator.suspendSpokenWriteHold()
    coordinator.endSpokenWriteHold()
    #expect(SessionCoordinator.activeSetID(for: try card(coordinator, in: session).set) == secondBench)

    coordinator.deleteLog(for: held)

    let cleared = try card(coordinator, in: session)
    #expect(cleared.mode == .logging)
    #expect(cleared.set === held)
    #expect(cleared.set.isPending)
}

@MainActor
@Test func aTouchThatArrivesWithNoHoldLeavesAnOpenReviewOpen() throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let logged = try card(coordinator, in: session).set
    coordinator.log(logged, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    coordinator.focus(on: logged)
    let motionsBeforeTheTouch = ledger.motions

    coordinator.endSpokenWriteHold()

    #expect(try card(coordinator, in: session).mode == .reviewingLogged(showsSavedConfirmation: false))
    #expect(ledger.motions == motionsBeforeTheTouch)
}

@MainActor
@Test func tappingTheHeldSetsLeafEndsTheHoldAndItsTimer() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)

    coordinator.focus(on: try card(coordinator, in: session).set)

    #expect(SessionCoordinator.activeSetID(for: try card(coordinator, in: session).set) == secondBench)
    let motionsAfterTheTap = ledger.motions
    await clock.waitForSleep()
    await clock.advance()
    #expect(ledger.motions == motionsAfterTheTap)
}

@MainActor
@Test func aSpokenSetLogInASupersetMovesOnAtOnceAsALogTapDoes() async throws {
    let session = makeSquatAndRDLSession()
    let (coordinator, _, clock) = makeDictationCoordinator(session: session, saying: ["225 for 5 at 7"])
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    #expect(coordinator.createSuperset(from: squat, to: rdl, in: session))
    let slot = try #require(supersetStage(coordinator, in: session)?.card)

    coordinator.startDictation(for: slot.set)
    _ = await coordinator.finishDictation(of: slot.set, resolvingAgainst: SpokenSetContext(for: slot.set, history: .empty).draft)

    let next = try #require(supersetStage(coordinator, in: session)?.card)
    #expect(next.mode == .logging)
    #expect(SessionCoordinator.activeSetID(for: next.set) == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(clock.sleptDurations.isEmpty)
}

@MainActor
@Test func aSetLogFilledFromSpeechWritesNothingAndFillsTheCard() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["13549", "135 for 4 at 9"])

    let outcome = try await sayIntoTheCard(coordinator, in: session)

    let filled = SetLogDraft(weight: .pounds(135), reps: 4, rpe: .nine)
    #expect(outcome == .filled(filled, heard: "13549"))
    #expect(ledger.entries.isEmpty)
    let slot = try card(coordinator, in: session)
    #expect(slot.mode == .logging)
    #expect(coordinator.cardDictation(for: slot) == .filled(filled))
}

@MainActor
@Test func aRejectedTranscriptWritesNothingAndTheCardShowsWhatWasHeard() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["100 kilos for 5"])

    _ = try await sayIntoTheCard(coordinator, in: session)

    #expect(ledger.entries.isEmpty)
    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .rejected(caption: "“100 kilos for 5”"))
}

@MainActor
@Test func aRejectionIsGoneOnceTheSetIsLoggedByHandAndCleared() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["100 kilos for 5"])
    _ = try await sayIntoTheCard(coordinator, in: session)
    let rejected = try card(coordinator, in: session)

    coordinator.log(SetLog(weight: .pounds(225), reps: 5, rpe: .seven), for: rejected)
    coordinator.deleteLog(for: rejected.set)

    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .ready)
}

@MainActor
@Test func aRejectionIsGoneOnceTheCardLeavesTheSetAndComesBack() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["100 kilos for 5"])
    _ = try await sayIntoTheCard(coordinator, in: session)
    let rejected = try card(coordinator, in: session)
    let squat = try #require(session.exercises.first { $0.order == 0 }?.sets.first)

    coordinator.focus(on: squat)
    coordinator.focus(on: rejected.set)

    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .ready)
}

@MainActor
@Test func aRejectionIsGoneOnceTheCoordinatorRebinds() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["100 kilos for 5"])
    _ = try await sayIntoTheCard(coordinator, in: session)

    coordinator.view(session)

    #expect(coordinator.cardDictation(for: try card(coordinator, in: session)) == .ready)
}
