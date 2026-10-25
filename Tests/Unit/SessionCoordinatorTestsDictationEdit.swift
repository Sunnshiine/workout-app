import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func reviewFirstBenchLoggedByHand(
    saying candidates: [String]
) throws -> (coordinator: SessionCoordinator, ledger: SessionVerbLedger, session: Session, set: ExerciseSet, restTimer: RestTimer) {
    let session = makeCoordinatorSession()
    let restTimer = RestTimer(
        clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0)),
        expiryScheduler: HeldRestExpiry()
    )
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: candidates, restTimer: restTimer)
    let set = try card(coordinator, in: session).set
    coordinator.log(set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    restTimer.dismiss()
    coordinator.focus(on: set)
    return (coordinator, ledger, session, set, restTimer)
}

@MainActor
@Test func aLoggedSetUnderReviewTakesTheMicAsAPendingSetDoes() throws {
    let (coordinator, _, session, set, _) = try reviewFirstBenchLoggedByHand(saying: ["190 for 6 at 8"])

    let reviewed = try card(coordinator, in: session)

    #expect(reviewed.set === set)
    #expect(reviewed.mode == .reviewingLogged(showsSavedConfirmation: false))
    #expect(coordinator.cardDictation(for: reviewed) == .ready)
}

@MainActor
@Test func aSpokenSetOverALoggedSetUnderReviewSavesItAsTheReviewsOwnSaveDoes() async throws {
    let (coordinator, ledger, session, set, restTimer) = try reviewFirstBenchLoggedByHand(saying: ["190 for 6 at 8"])
    let entriesBeforeThePress = ledger.entries.count

    let outcome = try await sayIntoTheCard(coordinator, in: session)

    let edited = SetLog(weight: .pounds(190), reps: 6, rpe: .eight)
    #expect(outcome == .logged(edited, heard: "190 for 6 at 8"))
    #expect(set.setLog == edited)
    #expect(ledger.entries.dropFirst(entriesBeforeThePress) == [.logged, .liveActivityReconciled, .flushRequested])
    #expect(!restTimer.isRunning)
    #expect(coordinator.activeSetID == secondBench)
    #expect(coordinator.savedLoggedSetID == firstBench)
}

@MainActor
@Test func aSpokenSetOverALoggedSetFillsWhatItLeavesOutFromWhatTheReviewShows() async throws {
    let (coordinator, _, _, set, _) = try reviewFirstBenchLoggedByHand(saying: ["for 4"])
    coordinator.cardShows(SetLogDraft(weight: .pounds(195), reps: 6, rpe: .nine), for: set)
    coordinator.startDictation(for: set)

    _ = await coordinator.finishDictation(of: set)

    #expect(set.setLog == SetLog(weight: .pounds(195), reps: 4, rpe: .nine))
}

@MainActor
@Test func aSecondReviewOfASetEditedBySpeechStillTakesTheMic() async throws {
    let (coordinator, _, session, set, _) = try reviewFirstBenchLoggedByHand(saying: ["190 for 6 at 8"])
    _ = try await sayIntoTheCard(coordinator, in: session)

    coordinator.focus(on: set)

    let reviewed = try card(coordinator, in: session)
    #expect(reviewed.mode == .reviewingLogged(showsSavedConfirmation: true))
    #expect(coordinator.cardDictation(for: reviewed) == .ready)
}

@MainActor
@Test func aSpokenSkipOverALoggedSetUnderReviewWritesNothing() async throws {
    let (coordinator, ledger, session, set, _) = try reviewFirstBenchLoggedByHand(saying: ["skip"])
    let entriesBeforeThePress = ledger.entries.count

    let outcome = try await sayIntoTheCard(coordinator, in: session)

    #expect(outcome == nil, "the card answers no skip it did not make")
    #expect(set.state == .logged)
    #expect(set.setLog == SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(ledger.entries.count == entriesBeforeThePress)
    #expect(coordinator.activeSetID == secondBench)
}

@MainActor
@Test func aPressForThePendingSetDoesNotEditItOnceItIsLoggedByHandAndReopened() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["190 for 6 at 8"])
    let set = try card(coordinator, in: session).set
    coordinator.startDictation(for: set)
    let byHand = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    coordinator.log(set, as: byHand)
    coordinator.focus(on: set)

    _ = await coordinator.finishDictation(of: set)

    #expect(set.setLog == byHand)
}

@MainActor
@Test func aPressRefusedWhileAnotherIsInFlightLeavesThatPressesLogStanding() async throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["190 for 6 at 8"])
    let pending = try card(coordinator, in: session).set
    let squat = try #require(session.exercises.first { $0.order == 0 }?.sets.first)
    coordinator.startDictation(for: pending)
    coordinator.focus(on: squat)

    coordinator.startDictation(for: squat)
    _ = await coordinator.finishDictation(of: pending)

    #expect(pending.setLog == SetLog(weight: .pounds(190), reps: 6, rpe: .eight))
}
