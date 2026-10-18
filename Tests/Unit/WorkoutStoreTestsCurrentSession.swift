import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func theStoredCurrentSessionMatchesAFreshResolveAfterEveryWritePoint() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let sessions = try #require(store.block?.weeks.first?.sessions)
    func firstSet(ofDay day: Int) throws -> ExerciseSet {
        try #require(sessions.first { $0.dayNumber == day }?.exercises.first?.sets.first)
    }
    var stored: [String] = []
    func record() {
        let label = store.currentSession?.address.map { "Week \($0.week), Day \($0.day)" } ?? "None"
        #expect(label == store.currentSessionDebugInfo.resolvedCurrentSession)
        stored.append(label)
    }

    record()
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
    try store.log(try firstSet(ofDay: 2), as: log)
    record()
    try store.log(try firstSet(ofDay: 3), as: log)
    record()
    try store.skip(try firstSet(ofDay: 3))
    record()
    try store.deleteLog(for: try firstSet(ofDay: 2))
    record()
    store.reload()
    record()
    store.show(SessionAddress(week: 1, day: 2))
    store.makeViewedSessionCurrent()
    record()
    store.clearCurrentSessionPin()
    record()
    store.moveOn()
    record()

    #expect(
        stored == [
            "Week 1, Day 1", "Week 1, Day 2", "Week 1, Day 3", "Week 1, Day 2", "Week 1, Day 1",
            "Week 1, Day 1", "Week 1, Day 2", "Week 1, Day 1", "Week 1, Day 2"
        ]
    )
}

@MainActor
@Test func aWriteThatThrowsAfterMovingTheSetStillMovesTheStoredCurrentSession() throws {
    let fixture = try makeStore(lastPerformed: RefusingIndex())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let set = try #require(
        store.block?.weeks.first?.sessions.first { $0.dayNumber == 2 }?.exercises.first?.sets.first
    )

    #expect(throws: (any Error).self) {
        try store.log(set, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    }

    #expect(set.state == .logged)
    #expect(store.currentSession?.dayNumber == 2)
}

@MainActor
private final class CurrentSessionChanges {
    private(set) var count = 0

    init(watching store: WorkoutStore) {
        observe(store)
    }

    private func observe(_ store: WorkoutStore) {
        withObservationTracking {
            _ = store.currentSession
        } onChange: {
            MainActor.assumeIsolated {
                self.count += 1
                self.observe(store)
            }
        }
    }
}

@MainActor
@Test func observersHearTheCurrentSessionOnlyWhenItMoves() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let sessions = try #require(store.block?.weeks.first?.sessions)
    func firstSet(ofDay day: Int) throws -> ExerciseSet {
        try #require(sessions.first { $0.dayNumber == day }?.exercises.first?.sets.first)
    }
    let changes = CurrentSessionChanges(watching: store)
    var counts: [Int] = []

    store.reload()
    counts.append(changes.count)
    try store.log(try firstSet(ofDay: 1), as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    counts.append(changes.count)
    try store.log(try firstSet(ofDay: 2), as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    counts.append(changes.count)
    store.moveOn()
    counts.append(changes.count)

    #expect(counts == [0, 0, 1, 2])
}
