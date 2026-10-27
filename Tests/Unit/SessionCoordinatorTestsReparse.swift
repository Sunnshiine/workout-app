import Foundation
import Testing

@testable import WorkoutTracker

// A sync deletes the cached Block and inserts the one it parsed, so every Session the stage read
// before it is detached. Each test's `parsed` is the same Session as a sync parses it again: the
// same Session Coordinate in new models.

/// The real stores over the fresh-block workbook, with the coordinator on the Viewed Session as
/// the Session screen shows it. The sync adapter is a spy, so a refused write is visible and
/// nothing flushes until the test does.
@MainActor
private func makeStoreStage() async throws -> (app: WorkoutApplication, coordinator: SessionCoordinator, sync: SpySessionSyncAdapter) {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(wiring: .fixture(logging: app.workout, navigation: app.workout, sync: sync))
    coordinator.view(try #require(app.workout.viewedSession))
    return (app, coordinator, sync)
}

/// A Session no Block holds, as a sync leaves the one the stage read: Bench Press at order 1, where
/// `makeCoordinatorSession` puts it, with `setCount` Pending Sets.
private func makeDetachedBench(setCount: Int) -> (session: Session, bench: Exercise) {
    let session = Session(dayNumber: 1, date: nil)
    let bench = Exercise(name: "Bench Press", coachNote: nil, order: 1)
    bench.sets = (0..<setCount).map {
        ExerciseSet(index: $0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    }
    session.exercises = [bench]
    return (session, bench)
}

/// `makeCoordinatorSession` as a sync parses it after the coach moved DB Row above Bench Press:
/// the same Session, with DB Row's Set 1 where Bench Press's Set 1 was.
@MainActor
private func makeCoordinatorSessionWithRowAboveBench() throws -> Session {
    let parsed = makeCoordinatorSession()
    let bench = try #require(parsed.exercises.first { $0.order == 1 })
    let row = try #require(parsed.exercises.first { $0.order == 2 })
    (bench.order, row.order) = (2, 1)
    return parsed
}

/// The store refuses a write for a Set no Block holds (#1052), and the stage finds the Session
/// again by its coordinate, so the card it builds next writes the parsed Set.
@MainActor
@Test func aTapOnACardASyncReplacedIsRefusedAndTheCardBuiltAfterItWritesTheParsedSet() async throws {
    let (app, coordinator, sync) = try await makeStoreStage()
    let before = try #require(app.workout.viewedSession)
    let staleCard = try #require(exerciseStage(coordinator, in: before)?.card)
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)

    _ = try await app.sync()
    coordinator.log(log, for: staleCard)

    #expect(sync.reportedErrors.count == 1)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)

    let parsed = try #require(app.workout.viewedSession)
    #expect(parsed !== before)
    let card = try #require(exerciseStage(coordinator, in: parsed)?.card)
    coordinator.log(log, for: card)

    #expect(sync.reportedErrors.count == 1)
    #expect(card.set.setLog == log)
    let flush = try await app.flush()
    #expect(flush.written == flush.attempted && flush.written > 0)
    #expect(flush.conflictedWrites.isEmpty)
}

@MainActor
@Test func viewingTheSessionOnStageParsedAgainKeepsTheFocusOnTheSameSet() throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 2 }?.sets.first))

    coordinator.view(parsed)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    let card = try #require(exerciseStage(coordinator, in: parsed)?.card)
    #expect(card.set === parsed.exercises.first { $0.order == 2 }?.sets.first)
}

@MainActor
@Test func aSessionParsedAgainWithTheFocusedSetLoggedFocusesItsFirstPendingSet() throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 2 }?.sets.first))
    let parsedRow = try #require(parsed.exercises.first { $0.order == 2 }?.sets.first)
    parsedRow.setLog = SetLog(weight: .pounds(135), reps: 10, rpe: .seven)
    parsedRow.state = .logged

    coordinator.view(parsed)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func aReviewOfASetTheSessionParsedAgainStillHasLoggedStaysOpen() throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 0 }?.sets.first))
    #expect(coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    coordinator.view(parsed)

    #expect(coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func aReviewOfASetTheSessionParsedAgainHasPendingCloses() throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 0 }?.sets.first))
    try #require(parsed.exercises.first { $0.order == 0 }?.sets.first).state = .pending

    coordinator.view(parsed)

    #expect(coordinator.expandedLoggedSetID == nil)
}

@MainActor
@Test func aSetHeldAfterASpokenWriteStaysHeldInTheSessionParsedAgainWhileItIsLogged() async throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)
    let parsedSet = try #require(parsed.exercises.first { $0.order == 1 }?.sets.first)
    parsedSet.setLog = try card(coordinator, in: session).set.setLog
    parsedSet.state = .logged

    coordinator.view(parsed)

    let held = try card(coordinator, in: parsed)
    #expect(held.mode == .heldAfterSpokenWrite)
    #expect(held.set === parsedSet)
}

@MainActor
@Test func aSetHeldAfterASpokenWriteThatTheSessionParsedAgainHasPendingIsNoLongerHeld() async throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    _ = try await sayIntoTheCard(coordinator, in: session)
    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)

    coordinator.view(parsed)

    let shown = try card(coordinator, in: parsed)
    #expect(shown.mode == .logging)
    #expect(shown.set === parsed.exercises.first { $0.order == 1 }?.sets.first { $0.index == 1 })
}

@MainActor
@Test func aSetHeldAfterASpokenWriteThatTheSessionParsedAgainNoLongerHasIsNoLongerHeld() async throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 1 }))
    _ = try await sayIntoTheCard(coordinator, in: session)
    #expect(try card(coordinator, in: session).mode == .heldAfterSpokenWrite)
    let parsedBench = try #require(parsed.exercises.first { $0.order == 1 })
    parsedBench.sets = parsedBench.sets.filter { $0.index == 0 }

    coordinator.view(parsed)

    #expect(coordinator.focusManager.visualFocusOwner == .activeSet(try #require(coordinator.activeSetID)))
}

@MainActor
@Test func aPressASyncLandsUnderLogsTheDictatedSetOfTheSessionParsedAgain() async throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let pressed = try card(coordinator, in: session).set
    coordinator.startDictation(for: pressed)

    coordinator.view(parsed)
    let released = try card(coordinator, in: parsed).set
    let outcome = await coordinator.finishDictation(of: released)

    let logged = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    #expect(outcome == .logged(logged, heard: "185 for 6 at 7"))
    #expect(released.setLog == logged)
    #expect(pressed.isPending)
    #expect(ledger.entries.filter { $0 == .logged }.count == 1)
}

/// The Set in the pressed Set's place after the sync is another Exercise's, so what was said for
/// Bench Press lands on neither, and the press is cancelled: a record decided for DB Row would
/// label it in an export as if the press had written it.
@MainActor
@Test func aPressWhoseSetASyncMovesWritesNothingToTheSetNowInItsPlace() async throws {
    let session = makeCoordinatorSession()
    let parsed = try makeCoordinatorSessionWithRowAboveBench()
    let journal = DictationJournal(storage: .inMemory)
    let dictation = SetDictation(
        transcriber: CannedSetTranscriber(candidates: ["185 for 6 at 7"]),
        reader: CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent))),
        journal: journal
    )
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, dictation: dictation)
    coordinator.startDictation(for: try card(coordinator, in: session).set)

    coordinator.view(parsed)
    let released = try card(coordinator, in: parsed).set
    let outcome = await coordinator.finishDictation(of: released)

    #expect(outcome == nil)
    #expect(released.isPending)
    #expect(ledger.entries.filter { $0 == .logged }.isEmpty)
    #expect(coordinator.dictation?.state == .idle)
    let endings = try await journal.records().map(\.ending)
    #expect(endings == [.cancelled])
}

/// A press names the place its Set was in, so a release on its own Set after a sync moved that
/// Set to another place is cancelled, as a release on any other Set is.
@MainActor
@Test func aPressReleasedOnItsSetAfterASyncMovedItIsCancelled() async throws {
    let session = makeCoordinatorSession()
    let parsed = try makeCoordinatorSessionWithRowAboveBench()
    let journal = DictationJournal(storage: .inMemory)
    let dictation = SetDictation(
        transcriber: CannedSetTranscriber(candidates: ["185 for 6 at 7"]),
        reader: CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent))),
        journal: journal
    )
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, dictation: dictation)
    coordinator.startDictation(for: try card(coordinator, in: session).set)

    coordinator.view(parsed)
    let movedBench = try #require(parsed.exercises.first { $0.order == 2 }?.sets.first { $0.index == 0 })
    let outcome = await coordinator.finishDictation(of: movedBench)

    #expect(outcome == nil)
    #expect(movedBench.isPending)
    #expect(ledger.entries.filter { $0 == .logged }.isEmpty)
    let endings = try await journal.records().map(\.ending)
    #expect(endings == [.cancelled])
}

@MainActor
@Test func aSyncThatLandsWhileTheCardListensHandsFreeLogsTheSetOfTheSessionParsedAgain() async throws {
    let session = makeCoordinatorSession()
    let parsed = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    let slot = try fixture.card(in: session)
    let listening = Task { await fixture.coordinator.listenHandsFree(to: slot.set) }
    await fixture.clock.waitUntilSleeping(until: VoiceActivity.frameDuration, orRecord: "The card never listened")

    fixture.navigation.currentSession = parsed
    fixture.navigation.liveEdgeOfSession = { $0 === parsed ? .atLiveEdge(currentSession: parsed) : .browsedAway }
    fixture.show(parsed)
    fixture.clock.advance(by: SetDictation.silenceWindow)
    let outcome = await listening.value

    let logged = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    #expect(outcome == .logged(logged, heard: "185 for 6 at 7"))
    let setID = try #require(SessionCoordinator.activeSetID(for: slot.set))
    let parsedSet = try #require(parsed.exercises.first { $0.order == setID.exerciseOrder }?.sets.first { $0.index == setID.setIndex })
    #expect(parsedSet.setLog == logged)
    #expect(slot.set.isPending)
}

/// The Set in the listened Set's place after the sync is another Exercise's, so what was heard for
/// Bench Press lands on neither.
@MainActor
@Test func aListenWhoseSetASyncMovesWritesNothingToTheSetNowInItsPlace() async throws {
    let session = makeCoordinatorSession()
    let parsed = try makeCoordinatorSessionWithRowAboveBench()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    let slot = try fixture.card(in: session)
    let listening = Task { await fixture.coordinator.listenHandsFree(to: slot.set) }
    await fixture.clock.waitUntilSleeping(until: VoiceActivity.frameDuration, orRecord: "The card never listened")

    fixture.navigation.currentSession = parsed
    fixture.navigation.liveEdgeOfSession = { $0 === parsed ? .atLiveEdge(currentSession: parsed) : .browsedAway }
    fixture.show(parsed)
    fixture.clock.advance(by: SetDictation.silenceWindow)

    #expect(await listening.value == nil)
    let row = try #require(parsed.exercises.first { $0.order == 1 })
    #expect(row.sets.allSatisfy { $0.isPending })
    #expect(fixture.ledger.entries.filter { $0 == .logged }.isEmpty)
    #expect(fixture.dictation?.state == .idle)
}

/// The Session screen follows the Current Session, so a sync that moves it moves the stage too,
/// and the listen it began on writes nothing.
@MainActor
@Test func aListenWhoseSessionASyncMakesNoLongerCurrentWritesNothing() async throws {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let (next, _) = makeSingleSetSession(dayNumber: 2)
    let fixture = makeHandsFreeFixture(showing: current, current: current)
    let slot = try fixture.card(in: current)
    let listening = Task { await fixture.coordinator.listenHandsFree(to: slot.set) }
    await fixture.clock.waitUntilSleeping(until: VoiceActivity.frameDuration, orRecord: "The card never listened")

    fixture.navigation.currentSession = next
    fixture.show(next)
    fixture.clock.advance(by: SetDictation.silenceWindow)

    #expect(await listening.value == nil)
    #expect(slot.set.isPending)
    #expect(fixture.ledger.entries.filter { $0 == .logged }.isEmpty)
    #expect(fixture.dictation?.state == .idle)
}

/// A Set whose Session no Block holds names no stage, so it neither writes nor moves the stage
/// off the Session it is on.
@MainActor
@Test func aTapOnASetOfADetachedSessionIsRefusedAndLeavesTheStageOnItsSession() throws {
    let session = makeCoordinatorSession()
    let detached = makeDetachedBench(setCount: 1)
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(logging: logging, sync: sync))
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 2 }?.sets.first))

    coordinator.log(try #require(detached.bench.sets.first), as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(logging.loggedSets.isEmpty)
    #expect(sync.reportedErrors == [String(describing: WorkoutLoggingError.detachedSession)])
    #expect(coordinator.sessionCoordinate == session.placement.coordinate)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
}

@MainActor
@Test func aPressOnASetOfADetachedSessionStartsNothing() throws {
    let session = makeCoordinatorSession()
    let detached = makeDetachedBench(setCount: 1)
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])

    coordinator.startDictation(for: try #require(detached.bench.sets.first))

    #expect(coordinator.dictation?.state == .idle)
}

/// A Detached Session is on no stage, so showing one moves the stage off the Session it was on,
/// as showing another Session does, and a press begun there writes nothing.
@MainActor
@Test func aPressBegunBeforeADetachedSessionIsShownWritesNothing() async throws {
    let session = makeCoordinatorSession()
    let detached = makeDetachedBench(setCount: 1)
    let (coordinator, ledger, _) = makeDictationCoordinator(session: session, saying: ["185 for 6 at 7"])
    let pressed = try card(coordinator, in: session).set
    coordinator.startDictation(for: pressed)

    coordinator.view(detached.session)
    let outcome = await coordinator.finishDictation(of: pressed)

    #expect(outcome == nil)
    #expect(pressed.isPending)
    #expect(ledger.entries.filter { $0 == .logged }.isEmpty)
    #expect(coordinator.dictation?.state == .idle)
}

@MainActor
@Test func theActiveSetOfADetachedSessionIsItsFirstPendingSetWhereverTheFocusIs() throws {
    let session = makeCoordinatorSession()
    let detached = makeDetachedBench(setCount: 2)
    let focus = ActiveSetFocusManager(session: session)
    focus.focus(on: try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 1 }))

    #expect(focus.activeSet(in: detached.session)?.set === detached.bench.sets.first { $0.index == 0 })
}
