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
private func sortedSessions(in block: Block) -> [Session] {
    block.weeks
        .sorted { $0.number < $1.number }
        .flatMap { $0.sessions.sorted { $0.dayNumber < $1.dayNumber } }
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
@Test func fallsBackToFirstAvailableSessionWhenNothingLogged() {
    let block = makeBlock()
    let current = SessionProgressTracker().currentSession(in: block)
    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 1)
}

@MainActor
@Test func fallsBackToFirstAvailableSessionWhenEarlierSessionsAreUnavailable() {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    sessions[0].exercises = []
    sessions[1].exercises = []

    let current = SessionProgressTracker().currentSession(in: block)

    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 3)
}

@MainActor
@Test func currentSessionIsNilWhenNoSessionsAreAvailable() {
    let block = makeBlock()
    for session in sortedSessions(in: block) {
        session.exercises = []
    }

    let current = SessionProgressTracker().currentSession(in: block)

    #expect(current == nil)
}

@MainActor
@Test func nextSessionSkipsUnavailableSessionsAndEndsAtLastAvailableSession() throws {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    let tracker = SessionProgressTracker()
    sessions[3].exercises = []

    let week1Day3 = sessions[2]
    let week2Day1 = try #require(tracker.nextSession(after: week1Day3, in: block))

    #expect(week2Day1.week?.number == 2)
    #expect(week2Day1.dayNumber == 1)
    #expect(tracker.nextSession(after: sessions[7], in: block) == nil)
}

@MainActor
@Test func hasSessionAheadIncludesUnavailableSessions() {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    sessions[1].exercises = []
    sessions[2].exercises = []
    sessions[3].exercises = []

    let tracker = SessionProgressTracker()

    #expect(tracker.hasSessionAhead(after: sessions[0], in: block))
    #expect(!tracker.hasSessionAhead(after: sessions[7], in: block))
}

@MainActor
@Test func sessionOrderRoundTripsAcrossBlock() throws {
    let block = makeBlock()
    let tracker = SessionProgressTracker()

    for session in sortedSessions(in: block) {
        let order = tracker.order(of: session)
        let roundTripped = try #require(tracker.session(at: order, in: block))

        #expect(roundTripped.persistentModelID == session.persistentModelID)
    }
}

@MainActor
@Test func currentSessionUsesValidOverrideEvenWhenBehindDerivedProgress() {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    sessions[2].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()

    let ahead = tracker.currentSession(in: block, overrideOrder: 5)
    let behind = tracker.currentSession(in: block, overrideOrder: 2)

    #expect(ahead?.week?.number == 2)
    #expect(ahead?.dayNumber == 1)
    #expect(behind?.week?.number == 1)
    #expect(behind?.dayNumber == 2)
}

@MainActor
@Test func currentSessionIgnoresUnavailableOverride() {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    sessions[1].exercises = []

    let current = SessionProgressTracker().currentSession(in: block, overrideOrder: 2)

    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 1)
}

@MainActor
@Test func currentSessionIgnoresInvalidOverride() {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    sessions[2].exercises[0].sets[0].state = .logged

    let current = SessionProgressTracker().currentSession(in: block, overrideOrder: 99)

    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 3)
}

@MainActor
@Test func currentSessionUsesPartialNotesLogsAsProgress() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE 8",
            "C37": "Day 1",
            "D39": "Sets", "F39": "Reps", "H39": "Load", "J39": "Last set RPE", "K39": "Notes",
            "C40": "Bench Press", "D40": "1", "F40": "5", "H40": "RPE 8", "K40": "Coach note",
            "K41": "185x5",
        ],
        rows: 45,
        cols: 30
    )
    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    let block = BlockBuilder.makeBlock(from: parsed.block)

    let current = try #require(SessionProgressTracker().currentSession(in: block))

    #expect(current.week?.number == 2)
    #expect(current.dayNumber == 1)
}

@MainActor
@Test func legacyLogCountsAllPrescribedSetsCompleteForSessionProgress() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12",
        ],
        rows: 24,
        cols: 30
    )
    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    let block = BlockBuilder.makeBlock(from: parsed.block)
    let session = try #require(block.weeks.first?.sessions.first)

    let presentation = SessionProgressHeaderPresentation(session: session)
    let tileState = SessionProgressTracker().tileState(for: session, currentSession: session)

    #expect(presentation.remainingSetCount == 0)
    #expect(presentation.completedSetCount == 2)
    #expect(tileState == .complete)
}

@MainActor
@Test func sessionTileStateHasFourCases() {
    #expect(SessionTileState.allCases == [.complete, .current, .incomplete, .unavailable])
}

@MainActor
@Test func tileStatePrioritizesCompletionOverCurrentSession() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises[0].sets[0].state = .logged

    let state = SessionProgressTracker().tileState(for: session, currentSession: session)

    #expect(state == .complete)
}

@MainActor
@Test func tileStateIsCurrentWhenCurrentSessionHasPendingWork() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]

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
@Test func tileStateIsIncompleteWhenNonCurrentSessionIsPartiallyLogged() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises[0].sets.append(
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    )
    session.exercises[0].sets[0].state = .logged

    let state = SessionProgressTracker().tileState(for: session, currentSession: nil)

    #expect(state == .incomplete)
}

@MainActor
@Test func tileStateDistinguishesPendingAvailableFromUnavailableSessions() {
    let block = makeBlock()
    let pendingSession = block.weeks[0].sessions[0]
    let unavailableSession = block.weeks[0].sessions[1]
    unavailableSession.exercises = []

    let tracker = SessionProgressTracker()

    #expect(tracker.tileState(for: pendingSession, currentSession: nil) == .incomplete)
    #expect(tracker.tileState(for: unavailableSession, currentSession: nil) == .unavailable)
}

@MainActor
@Test func tileStateIsUnavailableEvenWhenItIsTheCurrentSession() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises = []

    let state = SessionProgressTracker().tileState(for: session, currentSession: session)

    #expect(state == .unavailable)
}

@MainActor
@Test func openExercisesReturnsPendingExercisesFromPastSessionsInCurrentWeek() throws {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    let day1 = sessions[0]
    let day2 = sessions[1]
    let day3 = sessions[2]
    day1.exercises[0].sets.append(
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    )
    day1.exercises[0].sets[0].state = .logged
    day2.exercises[0].sets[0].state = .pending
    day3.exercises[0].sets[0].state = .logged

    let current = try #require(SessionProgressTracker().currentSession(in: block))
    let openExercises = SessionProgressTracker().openExercises(in: block, currentSession: current)

    #expect(openExercises.map(\.baseName) == ["Squat", "Squat"])
    #expect(openExercises.map { $0.session?.dayNumber } == [1, 2])
}

@MainActor
@Test func openExercisesEmptyOnFirstSessionOfWeek() throws {
    let block = makeBlock()
    let current = try #require(SessionProgressTracker().currentSession(in: block))

    let openExercises = SessionProgressTracker().openExercises(in: block, currentSession: current)

    #expect(openExercises.isEmpty)
}

@MainActor
@Test func openExercisesEmptyAfterAdvancingToNewWeek() throws {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    let week1Day1 = sessions[0]
    let week2Day1 = sessions[4]
    week1Day1.exercises[0].sets.append(
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    )
    week1Day1.exercises[0].sets[0].state = .logged
    week2Day1.exercises[0].sets[0].state = .logged

    let current = try #require(SessionProgressTracker().currentSession(in: block))
    let openExercises = SessionProgressTracker().openExercises(in: block, currentSession: current)

    #expect(current.week?.number == 2)
    #expect(openExercises.isEmpty)
}

@MainActor
@Test func openExercisesExcludesFullyLoggedPastSessions() throws {
    let block = makeBlock()
    let sessions = sortedSessions(in: block)
    let day1 = sessions[0]
    let day2 = sessions[1]
    day1.exercises[0].sets[0].state = .logged
    day2.exercises[0].sets[0].state = .logged

    let current = try #require(SessionProgressTracker().currentSession(in: block))
    let openExercises = SessionProgressTracker().openExercises(in: block, currentSession: current)

    #expect(current.dayNumber == 2)
    #expect(openExercises.isEmpty)
}
