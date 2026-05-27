import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func makeBlock() -> Block {
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: (1...2).map { w in
            ParsedWeek(
                number: w,
                days: (1...4).map { d in
                    ParsedSession(
                        dayNumber: d,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
                            )
                        ]
                    )
                }
            )
        }
    )
    return BlockBuilder.makeBlock(from: parsed)
}

@MainActor
@Test func currentSessionIsLatestWithALoggedSet() {
    let block = makeBlock()
    // Mark Week 1 / Day 3's only set as logged.
    block.weeks[0].sessions[2].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 3)
    #expect(tracker.currentWeek(in: block)?.number == 1)
}

@MainActor
@Test func fallsBackToFirstSessionWhenNothingLogged() {
    let block = makeBlock()
    let current = SessionProgressTracker().currentSession(in: block)
    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 1)
}

@MainActor
@Test func tileStatePrioritizesCurrentSession() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises[0].sets[0].state = .logged

    let state = SessionProgressTracker().tileState(for: session, currentSession: session)

    #expect(state == .current)
}

@MainActor
@Test func tileStateIsCompleteWhenEverySetIsLoggedOrSkipped() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises[0].sets[0].state = .skipped

    let state = SessionProgressTracker().tileState(for: session, currentSession: nil)

    #expect(state == .complete)
}

@MainActor
@Test func tileStateHasOpenExercisesWhenSomeSetsAreCompleted() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises[0].sets.append(
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    )
    session.exercises[0].sets[0].state = .logged

    let state = SessionProgressTracker().tileState(for: session, currentSession: nil)

    #expect(state == .hasOpenExercises)
}

@MainActor
@Test func tileStateIsUpcomingWhenSessionHasNoSetProgress() {
    let block = makeBlock()
    let pendingSession = block.weeks[0].sessions[0]
    let emptySession = block.weeks[0].sessions[1]
    emptySession.exercises = []

    let tracker = SessionProgressTracker()

    #expect(tracker.tileState(for: pendingSession, currentSession: nil) == .upcoming)
    #expect(tracker.tileState(for: emptySession, currentSession: nil) == .upcoming)
}
