import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
struct HandsFreeFixture {
    let coordinator: SessionCoordinator
    let ledger: SessionVerbLedger
    let navigation: SpySessionNavigationAdapter
    let entry: AppEntryInbox
    let dictation: SetDictation?
    let clock: ManualListeningClock

    /// Views `session` as the Session screen does when it shows it.
    func show(_ session: Session?) {
        guard let session else { return }
        coordinator.view(session)
    }

    func card(in session: Session) throws -> SetCardSlot {
        try #require(exerciseStage(coordinator, in: session)?.card)
    }

    /// Lets the card's listen run until the athlete has been quiet a silence window.
    func listenUntilQuiet(on slot: SetCardSlot, showing shown: @escaping @MainActor () -> SetLogDraft) async -> SetDictation.Outcome? {
        let listening = Task { await coordinator.listenHandsFree(to: slot.set, showing: shown) }
        await clock.waitUntilSleeping(until: SetDictation.silenceWindow, orRecord: "The card never listened")
        clock.advance(by: SetDictation.silenceWindow)
        return await listening.value
    }
}

/// `requested` delivers a request before the stage binds, as a cold launch from the Action button does.
@MainActor
func makeHandsFreeFixture(
    showing session: Session?,
    current: Session?,
    saying candidates: [String]? = ["185 for 6 at 7"],
    requested: Bool = true
) -> HandsFreeFixture {
    let clock = ManualListeningClock()
    let dictation = candidates.map { SetDictation(transcriber: CannedSetTranscriber(candidates: $0), clock: clock) }
    let entry = AppEntryInbox(clock: clock)
    if requested {
        entry.deliver(.dictateCurrentSet)
    }
    let ledger = SessionVerbLedger()
    let navigation = SpySessionNavigationAdapter(current: current)
    let fixture = HandsFreeFixture(
        coordinator: SessionCoordinator(
            wiring: .fixture(logging: ledger, navigation: navigation, sync: ledger, liveActivity: ledger, motion: ledger, entry: entry),
            transitionClock: ManualSessionTransitionClock(),
            dictation: dictation
        ),
        ledger: ledger,
        navigation: navigation,
        entry: entry,
        dictation: dictation,
        clock: clock
    )
    fixture.ledger.coordinator = fixture.coordinator
    fixture.show(session)
    return fixture
}

@MainActor
@Test func aRequestOnTheCurrentSessionListensForItsActiveSetAndWritesWhatIsSaidOnce() async throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    let slot = try fixture.card(in: session)
    #expect(fixture.coordinator.startsHandsFree(slot))
    #expect(fixture.entry.coverClosings > 0, "whatever covers the stage closes so the card can listen")

    let outcome = await fixture.listenUntilQuiet(on: slot) { SpokenSetContext(for: slot.set, history: .empty).draft }

    let logged = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    #expect(outcome == .logged(logged, heard: "185 for 6 at 7"))
    #expect(fixture.ledger.entries.filter { $0 == .logged }.count == 1)
    #expect(fixture.entry.pending == nil)
    let held = try fixture.card(in: session)
    #expect(held.mode == .heldAfterSpokenWrite)
    #expect(held.set.setLog == logged)
    #expect(!fixture.coordinator.startsHandsFree(held))
}

@MainActor
@Test func aRequestIsTakenOnceTheCardListensSoTheCardDoesNotListenTwice() async throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session)
    let slot = try fixture.card(in: session)

    let listening = Task { await fixture.coordinator.listenHandsFree(to: slot.set) { SetLogDraft(weight: nil, reps: nil, rpe: nil) } }
    await fixture.clock.waitUntilSleeping(until: SetDictation.silenceWindow, orRecord: "The card never listened")

    #expect(fixture.entry.pending == nil)
    #expect(!fixture.coordinator.startsHandsFree(slot))
    #expect(await fixture.coordinator.listenHandsFree(to: slot.set) { SetLogDraft(weight: nil, reps: nil, rpe: nil) } == nil)
    fixture.clock.advance(by: SetDictation.silenceWindow)
    _ = await listening.value
}

@MainActor
@Test func handsFreeListeningFillsWhatIsLeftUnsaidFromWhatTheCardShowsWhenItEnds() async throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session, saying: ["for 5 at 8"])
    let slot = try fixture.card(in: session)
    var shown = SetLogDraft(weight: nil, reps: nil, rpe: nil)

    let listening = Task { await fixture.coordinator.listenHandsFree(to: slot.set) { shown } }
    await fixture.clock.waitUntilSleeping(until: SetDictation.silenceWindow, orRecord: "The card never listened")
    shown = SetLogDraft(weight: .pounds(190), reps: 3, rpe: .seven)
    fixture.clock.advance(by: SetDictation.silenceWindow)

    #expect(await listening.value == .logged(SetLog(weight: .pounds(190), reps: 5, rpe: .eight), heard: "for 5 at 8"))
}

@MainActor
@Test func aRequestWhileAnotherSessionIsViewedShowsTheCurrentSessionThenListensThere() throws {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let (viewed, _) = makeSingleSetSession(dayNumber: 3)
    let fixture = makeHandsFreeFixture(showing: viewed, current: current)

    #expect(fixture.navigation.currentSessionShows == 1)
    #expect(fixture.entry.coverClosings > 0)
    #expect(!fixture.coordinator.startsHandsFree(try fixture.card(in: viewed)))
    #expect(fixture.entry.pending == .dictateCurrentSet)

    fixture.show(current)

    #expect(fixture.coordinator.startsHandsFree(try fixture.card(in: current)))
    #expect(fixture.navigation.currentSessionShows == 1)
}

@MainActor
@Test func withNoRequestWaitingTheStageStaysWhereItIsAndNoCardListensHandsFree() async throws {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let (viewed, _) = makeSingleSetSession(dayNumber: 3)
    let fixture = makeHandsFreeFixture(showing: current, current: current, requested: false)
    let slot = try fixture.card(in: current)

    #expect(!fixture.coordinator.startsHandsFree(slot))
    #expect(await fixture.coordinator.listenHandsFree(to: slot.set) { SetLogDraft(weight: nil, reps: nil, rpe: nil) } == nil)
    #expect(fixture.dictation?.state == .idle)

    fixture.show(viewed)
    fixture.coordinator.answerEntry()

    #expect(fixture.navigation.currentSessionShows == 0)
}

@MainActor
@Test func aRequestWhoseCurrentSessionHasNoPendingSetEndsWhereTheStageIs() throws {
    let (current, done) = makeSingleSetSession(dayNumber: 1)
    done.state = .logged
    let (viewed, _) = makeSingleSetSession(dayNumber: 3)
    let fixture = makeHandsFreeFixture(showing: viewed, current: current)

    #expect(fixture.navigation.currentSessionShows == 0)
    #expect(fixture.entry.coverClosings == 0)
    #expect(fixture.entry.pending == nil)
    #expect(fixture.ledger.entries == [.liveActivityReconciled])
}

@MainActor
@Test func aRequestWithNoCurrentSessionEndsWhereTheStageIs() throws {
    let (viewed, _) = makeSingleSetSession(dayNumber: 3)
    let fixture = makeHandsFreeFixture(showing: viewed, current: nil)

    #expect(fixture.navigation.currentSessionShows == 0)
    #expect(fixture.entry.coverClosings == 0)
    #expect(fixture.entry.pending == nil)
}

@MainActor
@Test func aRequestWithNoMicEndsWhereTheStageIs() throws {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let (viewed, _) = makeSingleSetSession(dayNumber: 3)
    let fixture = makeHandsFreeFixture(showing: viewed, current: current, saying: nil)

    #expect(fixture.navigation.currentSessionShows == 0)
    #expect(fixture.entry.coverClosings == 0)
    #expect(fixture.entry.pending == nil)
    fixture.show(current)
    #expect(!fixture.coordinator.startsHandsFree(try fixture.card(in: current)))
}

@MainActor
@Test func aRequestWaitsWhileTheStageHasNoSession() {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let fixture = makeHandsFreeFixture(showing: nil, current: current)

    #expect(fixture.entry.pending == .dictateCurrentSet)
    #expect(fixture.navigation.currentSessionShows == 0)
}

@MainActor
@Test func aRequestStillWaitingWhenItsLifetimeEndsIsNeverAnswered() throws {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let (viewed, _) = makeSingleSetSession(dayNumber: 3)
    let fixture = makeHandsFreeFixture(showing: nil, current: current)

    fixture.clock.advance(by: AppEntryInbox.requestLifetime)
    fixture.show(viewed)

    #expect(fixture.navigation.currentSessionShows == 0)
    fixture.show(current)
    #expect(!fixture.coordinator.startsHandsFree(try fixture.card(in: current)))
    #expect(fixture.entry.pending == nil, "no card can take the request")
}

@MainActor
@Test func aRequestThatHasWaitedJustUnderItsLifetimeIsAnsweredWhenTheStageShows() throws {
    let (current, _) = makeSingleSetSession(dayNumber: 1)
    let fixture = makeHandsFreeFixture(showing: nil, current: current)

    fixture.clock.advance(by: AppEntryInbox.requestLifetime - .milliseconds(1))
    fixture.show(current)

    #expect(fixture.coordinator.startsHandsFree(try fixture.card(in: current)))
}

@MainActor
@Test func aRequestThatArrivesWhileTheSignInRestoresListensAndLogsOnceTheRestoreSignsIn() async throws {
    let settings = SettingsStore(defaults: .inMemory())
    settings.setSpreadsheet(id: "SHEET123", title: "Training Log")
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: nil, current: session, requested: false)
    let reportOnboardingAsRootViewDoes = { fixture.entry.reportOnboarding(isShown: settings.needsOnboarding) }
    reportOnboardingAsRootViewDoes()

    fixture.entry.deliver(.dictateCurrentSet)
    settings.isSignedIn = true
    reportOnboardingAsRootViewDoes()
    fixture.show(session)

    let slot = try fixture.card(in: session)
    #expect(fixture.coordinator.startsHandsFree(slot))
    let outcome = await fixture.listenUntilQuiet(on: slot) { SpokenSetContext(for: slot.set, history: .empty).draft }
    #expect(outcome == .logged(SetLog(weight: .pounds(185), reps: 6, rpe: .seven), heard: "185 for 6 at 7"))
}

@MainActor
@Test func aRequestThatArrivesWhileTheStageShowsTheCurrentSessionIsAnsweredWhenItArrives() throws {
    let session = makeCoordinatorSession()
    let fixture = makeHandsFreeFixture(showing: session, current: session, requested: false)
    #expect(!fixture.coordinator.startsHandsFree(try fixture.card(in: session)))

    fixture.entry.deliver(.dictateCurrentSet)
    fixture.coordinator.answerEntry()

    #expect(fixture.coordinator.startsHandsFree(try fixture.card(in: session)))
}
