import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

/// A Reps Chip only turns the row, so a Set half chosen writes nothing.
@MainActor
@Test func aRepsChipTurnsTheRowToRPEAndWritesNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()

    let outcome = await harness.chooseReps(harness.identity(), reps: 6)

    #expect(outcome == .choseReps(6))
    #expect(harness.chosenReps == .some(6))
    #expect(harness.liveActivity.refreshes.count == 1)
    #expect(harness.liveActivity.readbacks.isEmpty)
    try harness.expectNothingWritten()
}

@MainActor
@Test func theBackChipTurnsTheRowBackToReps() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    _ = await harness.chooseReps(harness.identity(), reps: 6, on: chips)

    let outcome = await harness.chooseReps(harness.identity(), reps: nil, on: chips)

    #expect(outcome == .choseReps(nil))
    #expect(harness.chosenReps == .some(nil))
    try harness.expectNothingWritten()
}

/// The second tap of a double tap on a Reps Chip lands on the RPE Chip that took its place, and
/// must not log Reps the athlete tapped and an RPE they never chose.
@MainActor
@Test func anRPEChipAsTheRowTurnsWritesNothingAndOneAfterItLogs() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    _ = await harness.chooseReps(harness.identity(), reps: 6, on: chips)
    harness.clock.advance(by: .milliseconds(400))

    let early = await chips.logSet(setIdentity: harness.identity(), reps: 6, rpe: "7")

    #expect(early == .tooSoonAfterReps)
    #expect(harness.liveActivity.readbacks.isEmpty)
    #expect(harness.chosenReps == .some(6), "the row stays on RPE")
    try harness.expectNothingWritten()

    harness.clock.advance(by: LockScreenRows.rpeRowSettle)
    let outcome = await harness.press(harness.identity(), reps: 6, rpe: "7", on: chips)

    #expect(outcome == .logged(SetLog(weight: .pounds(235), reps: 6, rpe: .seven), at: firstSet))
}

/// The next Set's row starts on Reps, with nothing chosen.
@MainActor
@Test func theCardAfterALogOffersRepsAgain() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    _ = await harness.chooseReps(harness.identity(), reps: 6, on: chips)
    harness.clock.advance(by: LockScreenRows.rpeRowSettle)

    _ = await harness.press(harness.identity(), reps: 6, rpe: "7", on: chips)

    #expect(harness.liveActivity.restContent?.target?.setID == secondSet)
    #expect(harness.chosenReps == .some(nil))
}

@MainActor
@Test func aRepsChipOnALoggedSetWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let identity = harness.identity()
    _ = await harness.press(identity)

    let outcome = await harness.chooseReps(identity, reps: 6)

    #expect(outcome == .notLogged(.setSettled(setLog: "235×5 @7", set: try harness.squat(set: 1))))
    #expect(harness.liveActivity.readbacks.last == .settled(setLog: "235×5 @7", try harness.squat(set: 1)))
}

@MainActor
@Test(arguments: [("Block 26", 6, LockScreenPress.NotLogged.sessionChanged), ("Block 27", 0, .unreadable), ("Block 27", 101, .unreadable)])
func aRepsChipThatCannotTurnTheRowWritesNothingAndSaysSo(blockTab: String, reps: Int, why: LockScreenPress.NotLogged) async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()

    let outcome = await harness.chooseReps(harness.identity(blockTab: blockTab), reps: reps)

    #expect(outcome == .notLogged(why))
    #expect(harness.liveActivity.readbacks.first == .notLogged(why.caption))
    #expect(harness.liveActivity.refreshes.isEmpty)
    try harness.expectNothingWritten()
}

/// A locked phone has no header, so a press that logged nothing still shows the writes the Sheet
/// does not have yet.
@MainActor
@Test func aReadbackThatLoggedNothingCountsTheWritesStillQueued() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    try harness.app.workout.log(try #require(SessionSetOrder.orderedSets(in: session).first).set, as: logged235)

    _ = await harness.press(harness.identity(of: secondSet, blockTab: "Block 26"))

    guard case .set(let set) = harness.liveActivity.subjects.last else {
        Issue.record("The readback showed \(String(describing: harness.liveActivity.subjects.last))")
        return
    }
    #expect(set.pendingWrites == 1)
}
