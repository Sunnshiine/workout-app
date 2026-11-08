import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func heldBench() async throws -> (
    coordinator: SessionCoordinator, ledger: SessionVerbLedger, clock: ManualSessionTransitionClock, session: Session, held: ExerciseSet
) {
    let session = makeCoordinatorSession()
    let (coordinator, ledger, clock) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let held = try card(coordinator, in: session).set
    _ = try await sayIntoTheCard(coordinator, in: session)
    return (coordinator, ledger, clock, session, held)
}

@MainActor
private func viewedFixture(
    of session: Session
) -> (
    coordinator: SessionCoordinator, logging: SpySessionLoggingAdapter, sync: SpySessionSyncAdapter, navigation: SpySessionNavigationAdapter
) {
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let navigation = SpySessionNavigationAdapter()
    navigation.viewedSession = session
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: logging, navigation: navigation, sync: sync),
        transitionClock: ManualSessionTransitionClock()
    )
    return (coordinator, logging, sync, navigation)
}

private func anExercise(_ name: String, in session: Session) throws -> Exercise {
    try #require(session.exercises.first { $0.exerciseName.base == name })
}

@MainActor
@Test func theSheetOpeningKeepsTheHeldSetOnTheCardWhileItIsOpen() async throws {
    let (coordinator, ledger, clock, session, held) = try await heldBench()

    coordinator.beginFlagging(held)
    await clock.waitForSleep()
    await clock.advance()

    #expect(coordinator.setFlagSheet?.setLine == "Set 1 · 185×6 @7")
    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
    #expect(ledger.motions == [.momentumFlow])
}

@MainActor
@Test func theMoreMenuClosingUnderTheSheetLeavesTheHeldSetOnTheCard() async throws {
    let (coordinator, ledger, _, session, held) = try await heldBench()
    coordinator.suspendSpokenWriteHold()

    coordinator.beginFlagging(held)
    coordinator.endSpokenWriteHold()

    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
    #expect(ledger.motions == [.momentumFlow])
}

@MainActor
@Test func closingTheSheetMovesTheHeldSetOnAsClosingItsMenuDoes() async throws {
    let (coordinator, ledger, _, session, held) = try await heldBench()
    coordinator.suspendSpokenWriteHold()
    coordinator.beginFlagging(held)

    coordinator.endFlagging()

    #expect(coordinator.setFlagSheet == nil)
    let next = try card(coordinator, in: session)
    #expect(next.mode == .logging)
    #expect(SessionCoordinator.activeSetID(for: next.set) == secondBench)
    #expect(ledger.motions == [.momentumFlow, .momentumFlow])
}

@MainActor
@Test func closingTheSheetOverAReviewLeavesTheReviewOpen() throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _, _) = viewedFixture(of: session)
    let logged = try card(coordinator, in: session).set
    coordinator.log(logged, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    coordinator.focus(on: logged)

    coordinator.beginFlagging(logged)
    coordinator.endFlagging()

    #expect(try card(coordinator, in: session).mode == .reviewingLogged(showsSavedConfirmation: false))
}

@MainActor
@Test func raisingAFlagWritesItRequestsAFlushAndClosesTheSheet() throws {
    let session = makeCoordinatorSession()
    let (coordinator, logging, sync, _) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    coordinator.log(set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    let flushesBeforeTheFlag = sync.flushRequestCount
    let flag = try #require(SetFlag(kind: .pain, text: "left hip"))

    coordinator.beginFlagging(set)
    coordinator.raise(flag)

    #expect(logging.flaggedSets.map(\.set) == [set])
    #expect(logging.flaggedSets.map(\.flag) == [flag])
    #expect(sync.flushRequestCount == flushesBeforeTheFlag + 1)
    #expect(coordinator.setFlagSheet == nil)
    #expect(set.setFlagStanding == .unsynced)
}

@MainActor
@Test func aFlagTheStoreRefusesIsReportedAndNoFlushIsRequested() throws {
    let session = makeCoordinatorSession()
    let (coordinator, logging, sync, _) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    logging.error = .failed

    coordinator.beginFlagging(set)
    coordinator.raise(try #require(SetFlag(kind: .pain, text: nil)))

    #expect(logging.flaggedSets.isEmpty)
    #expect(sync.reportedErrors == [String(describing: TestLoggingError.failed)])
    #expect(sync.flushRequestCount == 0)
    #expect(coordinator.setFlagSheet == nil)
}

@MainActor
@Test func raisingWithNoSheetOpenWritesNothing() throws {
    let session = makeCoordinatorSession()
    let (coordinator, logging, sync, _) = viewedFixture(of: session)

    coordinator.raise(try #require(SetFlag(kind: .pain, text: nil)))

    #expect(logging.flaggedSets.isEmpty)
    #expect(sync.flushRequestCount == 0)
}

@MainActor
@Test func aSyncReplacingTheSessionKeepsTheSheetOnTheSameSet() throws {
    let session = makeCoordinatorSession()
    let (coordinator, logging, _, navigation) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    coordinator.beginFlagging(set)

    let reparsed = makeCoordinatorSession()
    navigation.viewedSession = reparsed
    let sameSet = try #require(try anExercise("Bench Press", in: reparsed).sets.first { $0.index == set.index })

    #expect(coordinator.setFlagSheet?.exerciseName == "Bench Press")
    coordinator.raise(try #require(SetFlag(kind: .pain, text: nil)))
    #expect(logging.flaggedSets.map(\.set) == [sameSet])
}

@MainActor
@Test func aSetTheCoachRemovedClosesTheSheetAndRaisesNothing() throws {
    let session = makeCoordinatorSession()
    let (coordinator, logging, _, navigation) = viewedFixture(of: session)
    coordinator.beginFlagging(try card(coordinator, in: session).set)

    let reparsed = makeCoordinatorSession()
    reparsed.exercises.removeAll { $0.exerciseName.base == "Bench Press" }
    navigation.viewedSession = reparsed

    #expect(coordinator.setFlagSheet == nil)
    coordinator.raise(try #require(SetFlag(kind: .pain, text: nil)))
    #expect(logging.flaggedSets.isEmpty)
}

@MainActor
@Test func aDraftOutlivesTheSheetThatClosedWithoutARaise() throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _, _) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    var draft = SetFlagDraft()
    draft.kind = .pain
    draft.words = "left hip"

    coordinator.beginFlagging(set)
    let id = try #require(coordinator.setFlagSheet?.id)
    coordinator.keepSetFlagDraft(draft, for: id)
    coordinator.endFlagging()
    coordinator.beginFlagging(set)

    #expect(coordinator.setFlagDraft(for: id) == draft)
}

@MainActor
@Test func eachSetKeepsItsOwnDraft() throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _, _) = viewedFixture(of: session)
    let bench = try anExercise("Bench Press", in: session).sets.sorted { $0.index < $1.index }
    let first = try #require(bench.first)
    let second = try #require(bench.dropFirst().first)
    var draft = SetFlagDraft()
    draft.words = "left hip"

    coordinator.beginFlagging(first)
    coordinator.keepSetFlagDraft(draft, for: try #require(coordinator.setFlagSheet?.id))
    coordinator.endFlagging()
    coordinator.beginFlagging(second)

    #expect(coordinator.setFlagDraft(for: try #require(coordinator.setFlagSheet?.id)) == SetFlagDraft())
}

@MainActor
@Test func aRaiseDropsTheSetsDraft() throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _, _) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    var draft = SetFlagDraft()
    draft.kind = .pain

    coordinator.beginFlagging(set)
    let id = try #require(coordinator.setFlagSheet?.id)
    coordinator.keepSetFlagDraft(draft, for: id)
    coordinator.raise(try #require(draft.flag))

    #expect(coordinator.setFlagDraft(for: id) == SetFlagDraft())
}

@MainActor
@Test func aFlagTheStoreRefusesKeepsTheSetsDraft() throws {
    let session = makeCoordinatorSession()
    let (coordinator, logging, _, _) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    var draft = SetFlagDraft()
    draft.kind = .pain
    draft.words = "left hip"
    logging.error = .failed

    coordinator.beginFlagging(set)
    let id = try #require(coordinator.setFlagSheet?.id)
    coordinator.keepSetFlagDraft(draft, for: id)
    coordinator.raise(try #require(draft.flag))

    #expect(coordinator.setFlagDraft(for: id) == draft)
}

@MainActor
@Test func aNewSessionOnStageDropsEveryDraft() throws {
    let session = makeCoordinatorSession()
    let (coordinator, _, _, navigation) = viewedFixture(of: session)
    let set = try card(coordinator, in: session).set
    var draft = SetFlagDraft()
    draft.words = "left hip"
    coordinator.beginFlagging(set)
    let id = try #require(coordinator.setFlagSheet?.id)
    coordinator.keepSetFlagDraft(draft, for: id)
    coordinator.endFlagging()

    let (next, _) = makeSingleSetSession(dayNumber: 2)
    navigation.viewedSession = next
    coordinator.view(next)

    #expect(coordinator.setFlagDraft(for: id) == SetFlagDraft())
}
