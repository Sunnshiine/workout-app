import Foundation
import Testing

@testable import WorkoutTracker

/// Week 1 Day `day`: a Back Squat with no Coach Note, then a BB RDL whose note prescribes a 10 s
/// Opening Hold. Two built are one Session parsed twice, as by a sync.
@MainActor
private func makeOpeningHoldSession(day: Int) -> Session {
    let session = Session(dayNumber: day, date: nil)
    let squat = Exercise(name: "Back Squat", coachNote: nil, order: 0)
    let rdl = Exercise(name: "2-3:1:0 BB RDL", coachNote: "Start w/ 10 sec hold, proceed to rep range.", order: 1)
    for exercise in [squat, rdl] {
        exercise.sets = (0..<2).map {
            ExerciseSet(index: $0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
        }
    }
    session.exercises = [squat, rdl]
    return placedInBlock(session)
}

@MainActor
private struct CountdownCoordinatorHarness {
    let session = makeOpeningHoldSession(day: 1)
    let time: SteppedCountdownTime
    let cues: RecordingCountdownCues
    let restTimer: RestTimer
    let liveActivity = SpySessionLiveActivityAdapter()
    let coordinator: SessionCoordinator

    init() {
        let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0))
        time = SteppedCountdownTime(clock: clock)
        cues = RecordingCountdownCues(clock: clock)
        restTimer = RestTimer(clock: clock, expiryScheduler: HeldRestExpiry())
        coordinator = SessionCoordinator(
            session: session,
            wiring: .fixture(
                logging: SpySessionLoggingAdapter(),
                restTimer: restTimer,
                countdown: EffortCountdown(clock: clock, scheduler: time, cues: cues),
                liveActivity: liveActivity
            )
        )
    }

    func rdlSet(_ index: Int) throws -> ExerciseSet {
        try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == index })
    }

    /// Focuses the RDL's first Set and taps its countdown.
    func startTheRDLsHold() throws -> SetCardSlot {
        coordinator.focus(on: try rdlSet(0))
        let slot = try card(coordinator, in: session)
        coordinator.startCountdown(for: slot)
        return slot
    }
}

@MainActor
@Test func everyPendingSetOfAnExerciseWhoseNoteHoldsAtTheStartOffersTheHold() throws {
    let harness = CountdownCoordinatorHarness()

    let squatCard = try card(harness.coordinator, in: harness.session)
    harness.coordinator.focus(on: try harness.rdlSet(0))
    let firstRDLCard = try card(harness.coordinator, in: harness.session)
    harness.coordinator.focus(on: try harness.rdlSet(1))
    let secondRDLCard = try card(harness.coordinator, in: harness.session)

    #expect(harness.coordinator.cardCountdown(for: squatCard) == nil)
    #expect(harness.coordinator.cardCountdown(for: firstRDLCard)?.effort.duration.seconds == 10)
    #expect(harness.coordinator.cardCountdown(for: secondRDLCard)?.effort.duration.seconds == 10)
    #expect(harness.coordinator.cardCountdown(for: secondRDLCard)?.run == nil)
}

@MainActor
@Test func aCardThatDoesNotLogItsSetOffersNoCountdown() throws {
    let harness = CountdownCoordinatorHarness()
    let set = try harness.rdlSet(0)

    let review = SetCardSlot(set: set, ordinal: 1, count: 2, mode: .reviewingLogged(showsSavedConfirmation: false), cardIdentity: "review")
    let held = SetCardSlot(set: set, ordinal: 1, count: 2, mode: .heldAfterSpokenWrite, cardIdentity: "held")

    #expect(harness.coordinator.cardCountdown(for: review) == nil)
    #expect(harness.coordinator.cardCountdown(for: held) == nil)
}

@MainActor
@Test func oneTapStartsTheLeadInAndEndsTheRestStillRunning() throws {
    let harness = CountdownCoordinatorHarness()
    harness.restTimer.start(duration: 120, origin: nil)

    let slot = try harness.startTheRDLsHold()

    #expect(harness.restTimer.interval == nil)
    #expect(harness.liveActivity.endCallCount == 1)
    #expect(harness.coordinator.cardCountdown(for: slot)?.run?.phase(at: harness.time.clock.now) == .leadIn(secondsLeft: 5))
    #expect(harness.cues.spoken == ["5"])
}

@MainActor
@Test func aSecondTapOnARunningCountdownDoesNotRestartIt() throws {
    let harness = CountdownCoordinatorHarness()
    let slot = try harness.startTheRDLsHold()
    harness.time.advance(by: 3)

    harness.coordinator.startCountdown(for: slot)

    #expect(harness.coordinator.countdown.run?.phase(at: harness.time.clock.now) == .leadIn(secondsLeft: 2))
    #expect(harness.cues.silences == 0)
}

@MainActor
@Test func theCountdownRunsOnlyOnTheCardOfItsSet() throws {
    let harness = CountdownCoordinatorHarness()
    _ = try harness.startTheRDLsHold()

    harness.coordinator.focus(on: try harness.rdlSet(1))
    let otherCard = try card(harness.coordinator, in: harness.session)

    #expect(harness.coordinator.cardCountdown(for: otherCard)?.run == nil)
}

@MainActor
@Test(
    "Logging, skipping, or moving the card off its Set ends the countdown and silences it",
    arguments: ["log", "skip", "focus", "jump"]
)
func leavingTheSetEndsTheCountdown(action: String) throws {
    let harness = CountdownCoordinatorHarness()
    let slot = try harness.startTheRDLsHold()
    harness.time.advance(by: 7)

    switch action {
    case "log": harness.coordinator.log(SetLog(weight: .pounds(225), reps: 8, rpe: .seven), for: slot)
    case "skip": harness.coordinator.skip(for: slot)
    case "focus": harness.coordinator.focus(on: try harness.rdlSet(1))
    default: harness.coordinator.jump(to: try #require(harness.session.exercises.first { $0.order == 0 }?.sets.first))
    }
    harness.time.advance(by: 30)

    #expect(harness.coordinator.countdown.run == nil)
    #expect(harness.cues.silences == 1)
    #expect(harness.cues.spoken.last == "Hold")
}

@MainActor
@Test func aSyncThatParsesTheSessionAgainKeepsTheCountdownOnItsSet() throws {
    let harness = CountdownCoordinatorHarness()
    _ = try harness.startTheRDLsHold()
    harness.time.advance(by: 7)
    let parsed = makeOpeningHoldSession(day: 1)

    harness.coordinator.view(parsed)
    harness.time.advance(by: 30)

    #expect(harness.cues.silences == 0)
    #expect(harness.cues.spoken.last == "Done")
}

@MainActor
@Test func viewingAnotherSessionEndsTheCountdown() throws {
    let harness = CountdownCoordinatorHarness()
    _ = try harness.startTheRDLsHold()
    let other = makeOpeningHoldSession(day: 2)

    harness.coordinator.view(other)

    #expect(harness.coordinator.countdown.run == nil)
    #expect(harness.cues.silences == 1)
}

@MainActor
@Test func movingOnEndsTheCountdown() throws {
    let harness = CountdownCoordinatorHarness()
    _ = try harness.startTheRDLsHold()

    harness.coordinator.moveOn()

    #expect(harness.coordinator.countdown.run == nil)
}

@MainActor
@Test func pressingTheMicEndsTheCountdownBeforeItListens() throws {
    let session = makeOpeningHoldSession(day: 1)
    let (coordinator, _, _) = makeDictationCoordinator(session: session, saying: ["225 for 8"])
    coordinator.focus(on: try #require(session.exercises.first { $0.order == 1 }?.sets.first))
    let slot = try card(coordinator, in: session)
    coordinator.startCountdown(for: slot)
    #expect(coordinator.countdown.run != nil)

    coordinator.startDictation(for: slot.set)

    #expect(coordinator.countdown.run == nil)
}
