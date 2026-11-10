import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func set(
    reps: String,
    load: String,
    in name: String = "Bench Press",
    note: String? = nil
) -> (session: Session, position: SessionSetPosition) {
    let exercise = Exercise(name: ExerciseName(entered: name), coachNote: note, order: 0)
    let set = ExerciseSet(index: 0, prescribedReps: reps, prescribedLoad: load, percentOneRM: nil, state: .pending)
    exercise.sets = [set]
    return (makeSingleSession(exercises: [exercise]), SessionSetPosition(exercise: exercise, set: set))
}

@MainActor
private func history(_ result: String, of name: String = "Bench Press") -> LastPerformedLookupSnapshot {
    LastPerformedLookupSnapshot(occurrences: [
        LastPerformedOccurrence(
            exerciseName: ExerciseName(entered: name),
            resultText: result,
            performedOn: Date(timeIntervalSinceReferenceDate: 1_000),
            source: "Block 26 · W4 D3"
        )
    ])
}

/// What the Lock Screen offers once the stage's card has shown `draft` for the Set.
@MainActor
private func press(
    _ fixture: (session: Session, position: SessionSetPosition),
    showing draft: SetLogDraft? = nil,
    history: LastPerformedLookupSnapshot = .empty
) -> LoggablePressContent {
    let focus = ActiveSetFocusManager(session: fixture.session)
    if let draft {
        focus.cardShows(draft, for: fixture.position.setID)
    }
    let shown = SpokenSetContext(for: fixture.position.set, shownBy: focus, history: history).draft
    return LoggablePressContent(for: fixture.position, following: fixture.session, showing: shown, history: history)
}

@MainActor
private func offer(_ content: LoggablePressContent) throws -> LockScreenOffer {
    guard case .ready(let offer) = content else { throw OfferedNoChips() }
    return offer
}

private struct OfferedNoChips: Error {}

@Test(arguments: [
    (RPE.five, ["5", "6", "6.5", "7", "7.5"]),
    (RPE.six, ["5", "6", "6.5", "7", "7.5"]),
    (RPE.seven, ["6", "6.5", "7", "7.5", "8"]),
    (RPE.nine, ["8", "8.5", "9", "9.5", "10"]),
    (RPE.ten, ["8", "8.5", "9", "9.5", "10"])
])
func theRPEChipsAreConsecutivePointsHeldInsideTheTable(center: RPE, labels: [String]) {
    #expect(RPE.chips(around: center).map(\.label) == labels)
}

@Test(arguments: [
    (1, [1, 2, 3, 4, 5]), (2, [1, 2, 3, 4, 5]), (8, [6, 7, 8, 9, 10]), (99, [96, 97, 98, 99, 100]), (100, [96, 97, 98, 99, 100])
])
func theRepsChipsAreConsecutiveValuesHeldInsideTheRail(center: Int, values: [Int]) {
    #expect(LockScreenOffer.repChoices(around: center) == values)
}

/// The card's Reps rail centres on a range's low end, the value it pre-fills, and ticks every
/// value of the range. Nothing is chosen ahead of the athlete.
@MainActor
@Test func aSetWithAWeightOffersRepsChipsAroundThePrescriptionWithNothingChosen() throws {
    let fixture = set(reps: "11-12", load: "RPE 8")

    let offered = try offer(press(fixture, showing: SetLogDraft(weight: .pounds(185), reps: nil, rpe: nil)))

    #expect(offered.repChoices == [9, 10, 11, 12, 13])
    #expect(offered.prescribedReps == [11, 12])
    #expect(offered.chosenReps == nil)
    #expect(offered.rpeChoices == ["7", "7.5", "8", "8.5", "9"])
    #expect(offered.prescribedRPE == "8")
    let identity = try #require(LoggableSetIdentity(storageValue: offered.setIdentity))
    #expect(identity.setID == fixture.position.setID)
    #expect(identity.session == fixture.session.placement.coordinate)
    #expect(identity.weight == .pounds(185))
}

/// The weight is whatever the stage holds, including one the athlete set before the Set.
@MainActor
@Test func theChipsCentreOnWhatTheCardShows() throws {
    let fixture = set(reps: "5", load: "RPE 7")

    let offered = try offer(press(fixture, showing: SetLogDraft(weight: .pounds(240), reps: 3, rpe: .eightPointFive)))

    #expect(offered.repChoices == [1, 2, 3, 4, 5])
    #expect(offered.prescribedReps == [5])
    #expect(offered.rpeChoices == ["7.5", "8", "8.5", "9", "9.5"])
    #expect(offered.prescribedRPE == "7", "the tick stays on what the coach wrote")
    #expect(LoggableSetIdentity(storageValue: offered.setIdentity)?.weight == .pounds(240))
}

/// The athlete chooses the Reps, so a Set whose Reps cell names no count logs from the Lock Screen.
@MainActor
@Test(arguments: ["AMRAP", "5+", "1-2-3-3-2-1"])
func aSetWithNoRepTargetOffersRepsChipsAroundTheRailsDefault(reps: String) throws {
    let offered = try offer(press(set(reps: reps, load: "BW")))

    #expect(offered.repChoices == [3, 4, 5, 6, 7])
    #expect(offered.prescribedReps.isEmpty)
}

/// A bodyweight Set's pre-fill needs no Last Performed, and with no RPE target the RPE Chips centre
/// on what the athlete last reported.
@MainActor
@Test func withNoPrescribedRPETheRPEChipsCentreOnLastPerformed() throws {
    let offered = try offer(press(set(reps: "5", load: "BW"), history: history("BWx5@6, BWx5@9")))

    #expect(offered.rpeChoices == ["8", "8.5", "9", "9.5", "10"])
    #expect(offered.prescribedRPE == nil)
}

@MainActor
@Test func withNoRPEAndNoStructuredLastPerformedTheRPEChipsCentreOnTheRailsDefault() throws {
    let offered = try offer(press(set(reps: "5", load: "BW"), history: history("felt heavy")))

    #expect(offered.rpeChoices == ["7", "7.5", "8", "8.5", "9"])
}

/// The index tracks the Session in progress, and every rest follows one of its Sets.
@MainActor
@Test func theRPEChipsSkipTheSessionInProgress() throws {
    let fixture = set(reps: "5", load: "BW")
    let today = try #require(fixture.session.placement.coordinate)
    let name = ExerciseName(entered: "Bench Press")
    let history = LastPerformedLookupSnapshot(occurrences: [
        LastPerformedOccurrence(
            exerciseName: name,
            resultText: "BWx5@6",
            performedOn: Date(timeIntervalSinceReferenceDate: 1_000),
            source: "Block 26 · W4 D3"
        ),
        LastPerformedOccurrence(
            exerciseName: name,
            resultText: "BWx5@9",
            performedOn: Date(timeIntervalSinceReferenceDate: 2_000),
            source: today.storageValue
        )
    ])

    #expect(try offer(press(fixture, history: history)).rpeChoices == RPE.chips(around: .six).map(\.label))
}

/// The weight is the one value the Lock Screen cannot choose, so a card that holds none sends the
/// athlete to the app.
@MainActor
@Test func aSetWithNoWeightOffersNoChips() {
    #expect(press(set(reps: "5", load: "RPE 7")) == .needsApp)
    #expect(press(set(reps: "5", load: "")) == .needsApp)
}

/// A Timed Set's card counts the effort, which a tap on a locked phone cannot, whatever it shows.
@MainActor
@Test func aTimedSetOffersNoChipsEvenWithACardReport() {
    let fixture = set(reps: "40 sec", load: "185")

    #expect(press(fixture, showing: SetLogDraft(weight: .pounds(185), reps: 40, rpe: nil)) == .needsApp)
}

@MainActor
@Test func anOpenExercisesSetInAnotherSessionOffersNoChips() {
    let earlier = set(reps: "5", load: "BW")
    let later = set(reps: "5", load: "BW", in: "Back Squat")

    let offer = LoggablePressContent(
        for: earlier.position,
        following: later.session,
        showing: SetLogDraft(weight: .bodyweight, reps: 5, rpe: nil),
        history: .empty
    )

    #expect(offer == .needsApp)
}

@Test(arguments: [Weight.pounds(237.5), Weight.pounds(1005), Weight.bodyweight])
func aSetIdentityReadsBackWhatItStored(weight: Weight) throws {
    let identity = LoggableSetIdentity(
        session: SessionCoordinate(blockTab: "Block 27 · Peaking", address: SessionAddress(week: 2, day: 3)),
        setID: ActiveSetID(exerciseOrder: 4, setIndex: 1),
        weight: weight
    )

    #expect(LoggableSetIdentity(storageValue: identity.storageValue) == identity)
}

/// The five-field identity of the one-tap card that carried its Reps reads as nothing, so a press
/// from a card drawn by an older build writes nothing.
@Test(arguments: [
    "", "Block 27 · W1 D1", "Block 27 · W1 D1\n0\n1", "Block 27 · W1 D1\nzero\n1\n235", "no session\n0\n1\n235",
    "Block 27 · W1 D1\n0\n1\n235\n5"
])
func aSetIdentityOfAnotherShapeReadsAsNothing(stored: String) {
    #expect(LoggableSetIdentity(storageValue: stored) == nil)
}

/// The Start names the Set by its place in its Session, as the stage's countdown does.
@MainActor
@Test func aSetWithAnOpeningHoldOffersTheStartForItsOwnSet() throws {
    let fixture = set(reps: "8", load: "RPE 8", in: "2-3:1:0 BB RDL", note: "Start w/ 10 sec hold")
    let session = try #require(fixture.session.placement.coordinate)

    let start = try #require(LockScreenStart(fixture.position))

    #expect(start.effort == .openingHold(try #require(EffortDuration("10 sec"))))
    #expect(start.request == .startTimedEffort(CountdownRun.Owner(session: session, set: fixture.position.setID)))
}

@MainActor
@Test func aSetWithNoTimedEffortOrNoLongerPendingOffersNoStart() {
    let plain = set(reps: "8", load: "RPE 8")
    let held = set(reps: "8", load: "RPE 8", note: "Start w/ 10 sec hold")
    held.position.set.markLogged(SetLog(weight: .pounds(135), reps: 8, rpe: .eight), at: Date(timeIntervalSinceReferenceDate: 0))

    #expect(LockScreenStart(plain.position) == nil)
    #expect(LockScreenStart(held.position) == nil)
}
