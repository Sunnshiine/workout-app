import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func set(reps: String, load: String, in name: String = "Bench Press") -> (session: Session, position: SessionSetPosition) {
    let exercise = Exercise(name: ExerciseName(entered: name), coachNote: nil, order: 0)
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

@MainActor
private func press(
    _ fixture: (session: Session, position: SessionSetPosition),
    history: LastPerformedLookupSnapshot,
    shownBy focus: ActiveSetFocusManager = ActiveSetFocusManager(session: nil)
) -> LoggablePressContent {
    LoggablePressContent(for: fixture.position, following: fixture.session, shownBy: focus, history: history)
}

@Test(arguments: [
    (RPE.five, ["5", "6", "6.5", "7", "7.5"]),
    (RPE.six, ["5", "6", "6.5", "7", "7.5"]),
    (RPE.seven, ["6", "6.5", "7", "7.5", "8"]),
    (RPE.nine, ["8", "8.5", "9", "9.5", "10"]),
    (RPE.ten, ["8", "8.5", "9", "9.5", "10"])
])
func theChipsAreConsecutivePointsHeldInsideTheTable(center: RPE, labels: [String]) {
    #expect(RPE.chips(around: center).map(\.label) == labels)
}

@MainActor
@Test func aCompletePreFillOffersChipsCentredOnThePrescribedRPE() throws {
    let fixture = set(reps: "5", load: "RPE 7")

    let offered = press(fixture, history: history("225x5@6"))
    guard case .ready(let weight, let reps, let choices, let prescribed, let setIdentity) = offered else {
        Issue.record("A Set with a Load Suggestion and a reps target offered no chips")
        return
    }

    #expect(reps == 5)
    #expect(choices == ["6", "6.5", "7", "7.5", "8"])
    #expect(prescribed == "7")
    let identity = try #require(LoggableSetIdentity(storageValue: setIdentity))
    #expect(identity.setID == fixture.position.setID)
    #expect(identity.session == fixture.session.placement.coordinate)
    #expect(identity.weight.label == weight)
    #expect(identity.reps == 5)
}

/// A bodyweight Set's pre-fill needs no Last Performed, and with no RPE target the chips centre on
/// what the athlete last reported.
@MainActor
@Test func withNoPrescribedRPETheChipsCentreOnLastPerformed() {
    let offered = press(set(reps: "5", load: "BW"), history: history("BWx5@6, BWx5@9"))
    guard case .ready(_, _, let choices, let prescribed, _) = offered else {
        Issue.record("A bodyweight Set offered no chips")
        return
    }

    #expect(choices == ["8", "8.5", "9", "9.5", "10"])
    #expect(prescribed == nil)
}

@MainActor
@Test func withNoRPEAndNoStructuredLastPerformedTheChipsCentreOnTheRailsDefault() {
    guard case .ready(_, _, let choices, _, _) = press(set(reps: "5", load: "BW"), history: history("felt heavy")) else {
        Issue.record("A bodyweight Set offered no chips")
        return
    }

    #expect(choices == ["7", "7.5", "8", "8.5", "9"])
}

@MainActor
@Test(arguments: [("AMRAP", "BW"), ("5+", "BW"), ("40 sec", "BW"), ("0:45", "BW"), ("5", "")])
func aPreFillMissingAValueOffersNoChips(reps: String, load: String) {
    #expect(press(set(reps: reps, load: load), history: .empty) == .needsApp)
}

@MainActor
@Test func aSetWithNoLoadSuggestionOffersNoChips() {
    #expect(press(set(reps: "5", load: "RPE 7"), history: .empty) == .needsApp)
}

/// A Timed Set's card counts the effort, which a tap on a locked phone cannot, whatever it shows.
@MainActor
@Test func aTimedSetOffersNoChipsEvenWithACardReport() {
    let fixture = set(reps: "40 sec", load: "185")
    let focus = ActiveSetFocusManager(session: fixture.session)
    focus.cardShows(SetLogDraft(weight: .pounds(185), reps: 40, rpe: nil), for: fixture.position.setID)

    #expect(press(fixture, history: .empty, shownBy: focus) == .needsApp)
}

/// The app logs what its card shows, so the Lock Screen does too.
@MainActor
@Test func theChipsLogWhatTheCardShows() throws {
    let fixture = set(reps: "5", load: "RPE 7")
    let focus = ActiveSetFocusManager(session: fixture.session)
    focus.cardShows(SetLogDraft(weight: .pounds(240), reps: 3, rpe: .eightPointFive), for: fixture.position.setID)

    guard case .ready(let weight, let reps, let choices, let prescribed, _) = press(fixture, history: .empty, shownBy: focus) else {
        Issue.record("A complete card offered no chips")
        return
    }

    #expect(weight == "240")
    #expect(reps == 3)
    #expect(choices == ["7.5", "8", "8.5", "9", "9.5"])
    #expect(prescribed == "7", "the tick stays on what the coach wrote")
}

/// A Sheet's AMRAP can be pre-filled too once the athlete picks reps on the card.
@MainActor
@Test func anAMRAPTheAthleteFilledOffersChips() {
    let fixture = set(reps: "AMRAP", load: "185")
    let focus = ActiveSetFocusManager(session: fixture.session)
    focus.cardShows(SetLogDraft(weight: .pounds(185), reps: 8, rpe: nil), for: fixture.position.setID)

    guard case .ready(_, let reps, _, _, _) = press(fixture, history: .empty, shownBy: focus) else {
        Issue.record("A filled card offered no chips")
        return
    }

    #expect(reps == 8)
}

@MainActor
@Test func anOpenExercisesSetInAnotherSessionOffersNoChips() {
    let earlier = set(reps: "5", load: "185")
    let later = set(reps: "5", load: "185", in: "Back Squat")

    let offer = LoggablePressContent(
        for: earlier.position,
        following: later.session,
        shownBy: ActiveSetFocusManager(session: nil),
        history: .empty
    )

    #expect(offer == .needsApp)
}

@Test(arguments: [Weight.pounds(237.5), Weight.pounds(1005), Weight.bodyweight])
func aSetIdentityReadsBackWhatItStored(weight: Weight) throws {
    let identity = LoggableSetIdentity(
        session: SessionCoordinate(blockTab: "Block 27 · Peaking", address: SessionAddress(week: 2, day: 3)),
        setID: ActiveSetID(exerciseOrder: 4, setIndex: 1),
        weight: weight,
        reps: 12
    )

    #expect(LoggableSetIdentity(storageValue: identity.storageValue) == identity)
}

@Test(arguments: ["", "Block 27 · W1 D1", "Block 27 · W1 D1\n0\n1\n235", "Block 27 · W1 D1\nzero\n1\n235\n5", "no session\n0\n1\n235\n5"])
func aSetIdentityOfAnotherShapeReadsAsNothing(stored: String) {
    #expect(LoggableSetIdentity(storageValue: stored) == nil)
}

@MainActor
@Test func theLastPerformedLinesGiveUpTheAddressThenWholeSetLogs() {
    let exercise = Exercise(name: ExerciseName(entered: "Bench Press"), coachNote: nil, order: 0)

    #expect(exercise.lastPerformedLines(in: .empty).isEmpty)
    #expect(exercise.lastPerformedLines(in: history("245x5@6")) == ["Block 26 · W4 D3 — 245×5 @6", "245×5 @6"])
    #expect(
        exercise.lastPerformedLines(in: history("245x5@6, 255x5@7, 265x5@8")) == [
            "Block 26 · W4 D3 — 245×5 @6, 255×5 @7, 265×5 @8",
            "245×5 @6, 255×5 @7, 265×5 @8",
            "245×5 @6, 255×5 @7, …",
            "245×5 @6, …"
        ]
    )
}

/// Five lines at most of 120 characters, whatever the Legacy Log, against the Live Activity's 4 KB.
@MainActor
@Test func theLastPerformedLinesStayShortForALongLegacyLog() {
    let exercise = Exercise(name: ExerciseName(entered: "Bench Press"), coachNote: nil, order: 0)

    let lines = exercise.lastPerformedLines(in: history(String(repeating: "felt heavy, ", count: 100)))

    #expect(lines.count == 5)
    #expect(lines.allSatisfy { $0.count <= 120 })
    #expect(lines.last == "felt heavy, …")
}

/// The index tracks the Session in progress, and every rest follows one of its Sets.
@MainActor
@Test func theCardsLastPerformedSkipsTheSessionInProgress() throws {
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

    #expect(fixture.position.exercise.lastPerformedLines(in: history).first == "Block 26 · W4 D3 — BW×5 @6")
    guard case .ready(_, _, let choices, _, _) = press(fixture, history: history) else {
        Issue.record("A bodyweight Set with a reps target offered no chips")
        return
    }
    #expect(choices == RPE.chips(around: .six).map(\.label))
}

/// A tier-3 match names the differently spelled entry, as the app's Last Performed line does.
@MainActor
@Test func theLastPerformedLinesNameAMovementLevelMatchUntilOnlyTheSetLogFits() {
    let exercise = Exercise(name: ExerciseName(entered: "Comp BP"), coachNote: nil, order: 0)

    let lines = exercise.lastPerformedLines(in: history("245x5@6", of: "Competition Bench Press"))

    #expect(
        lines == [
            "Block 26 · W4 D3 — 245×5 @6 as “Competition Bench Press”",
            "245×5 @6 as “Competition Bench Press”",
            "245×5 @6"
        ]
    )
}
