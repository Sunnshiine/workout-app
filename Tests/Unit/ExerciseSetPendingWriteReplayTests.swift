import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func replaySet(state: SetState, setLog: SetLog?, unstructuredSetLog: String? = nil) -> ExerciseSet {
    let set = ExerciseSet(
        index: 0,
        prescribedReps: "5",
        prescribedLoad: "RPE8",
        percentOneRM: nil,
        state: state,
        unstructuredSetLog: unstructuredSetLog
    )
    set.setLog = setLog
    set.loggedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    return set
}

private func replayWrite(
    operation: PendingWriteOperation = .upsert,
    valueToWrite: String?
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: operation,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

@MainActor
@Test func replayingAQueuedSetLogLogsTheSet() {
    let set = replaySet(state: .pending, setLog: nil)

    set.apply(replayWrite(valueToWrite: "185x5@8"))

    #expect(set.state == .logged)
    #expect(set.setLog == SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    #expect(set.loggedAt == Date(timeIntervalSinceReferenceDate: 0))
}

@MainActor
@Test func replayingTheSkipSentinelSkipsTheSetAndClearsItsLog() {
    let set = replaySet(state: .logged, setLog: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))

    set.apply(replayWrite(valueToWrite: "skip"))

    #expect(set.state == .skipped)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == nil)
}

@MainActor
@Test func replayingADeleteReturnsTheSetToPendingAndDropsItsFreeText() {
    let set = replaySet(state: .logged, setLog: nil, unstructuredSetLog: "felt heavy")

    set.apply(replayWrite(operation: .delete, valueToWrite: nil))

    #expect(set.state == .pending)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == nil)
    #expect(set.unstructuredSetLog == nil)
}

/// The parser reads unparseable text as logged-but-unstructured. The replay has no Set Log to put
/// on the Set, so it leaves the Set exactly as the parse left it.
@MainActor
@Test func replayingFreeTextLeavesTheSetUntouched() {
    let set = replaySet(state: .pending, setLog: nil)

    set.apply(replayWrite(valueToWrite: "worked up to a top single"))

    #expect(set.state == .pending)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == Date(timeIntervalSinceReferenceDate: 1_000))
}

@MainActor
@Test func replayingAnEmptyValueLeavesTheSetUntouched() {
    let set = replaySet(state: .logged, setLog: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))

    set.apply(replayWrite(valueToWrite: ""))

    #expect(set.state == .logged)
    #expect(set.setLog == SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    #expect(set.loggedAt == Date(timeIntervalSinceReferenceDate: 1_000))
}

@MainActor
@Test func replayingAWriteWithNoValueLeavesTheSetUntouched() {
    let set = replaySet(state: .logged, setLog: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))

    set.apply(replayWrite(valueToWrite: nil))

    #expect(set.state == .logged)
    #expect(set.setLog == SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
}
