import Testing
import WorkoutTracker

private func address(_ raw: String) throws -> SetAddress {
    try #require(SetAddress(raw))
}

@MainActor
@Test func deleteLogOnAPendingSetConverges() async throws {
    let app = try await makeSelectedApp()

    let report = try app.deleteLog(address("w1d1.e0.s0"))

    #expect(report.set.state == "pending")
    #expect(report.pendingWriteCount == 0)
}

@MainActor
@Test func deleteLogAfterALogEnqueuesOneWriteAndLeavesTheSetPending() async throws {
    let app = try await makeSelectedApp()
    let logged = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")

    let report = try app.deleteLog(address("w1d1.e0.s0"))

    #expect(logged.pendingWriteCount == 1)
    #expect(report.set.state == "pending")
    #expect(report.pendingWriteCount == 2)
}

@MainActor
@Test func makeCurrentOnTheCurrentSessionConverges() async throws {
    let app = try await makeSelectedApp()

    let snapshot = try app.makeCurrent()

    #expect(snapshot.currentSession == SessionAddress(week: 1, day: 1))
    #expect(snapshot.currentSessionIsOverridden == false)
}

@MainActor
@Test func makeCurrentPinsTheViewedSession() async throws {
    let app = try await makeSelectedApp()
    try app.view(SessionAddress(week: 2, day: 1))

    let snapshot = try app.makeCurrent()

    #expect(snapshot.currentSession == SessionAddress(week: 2, day: 1))
    #expect(snapshot.currentSessionIsOverridden == true)
}

@MainActor
@Test func makeCurrentRefusesAnUnavailableViewedSession() async throws {
    let app = try await makeSelectedApp()
    try app.view(SessionAddress(week: 2, day: 3))

    #expect(throws: ApplicationError.sessionUnavailable("w2d3")) { try app.makeCurrent() }
}

@MainActor
@Test func dismissingWithNoMoveOnCelebrationOpenRefuses() async throws {
    let app = try await makeSelectedApp()

    #expect(throws: ApplicationError.noMoveOnCelebration) { try app.dismissMoveOnCelebration() }
}

@MainActor
@Test func moveOnFromTheFirstSessionLandsOnTheNext() async throws {
    let app = try await makeSelectedApp()

    _ = try app.requestMoveOnCelebration()
    let report = try app.dismissMoveOnCelebration()

    #expect(report.returnedToBlockGrid == false)
    #expect(report.snapshot.currentSession == SessionAddress(week: 1, day: 2))
}

@MainActor
@Test func moveOnWithNoAvailableSessionAheadReturnsToTheBlockGrid() async throws {
    let app = try await makeSelectedApp()
    try app.view(SessionAddress(week: 2, day: 2))
    _ = try app.makeCurrent()

    _ = try app.requestMoveOnCelebration()
    let report = try app.dismissMoveOnCelebration()

    #expect(report.returnedToBlockGrid == true)
    #expect(report.snapshot.currentSession == SessionAddress(week: 2, day: 2))
}

@MainActor
@Test func theBlockGridReturnDoesNotCarryIntoTheNextMoveOn() async throws {
    let app = try await makeSelectedApp()
    try app.view(SessionAddress(week: 2, day: 2))
    _ = try app.makeCurrent()
    _ = try app.requestMoveOnCelebration()
    _ = try app.dismissMoveOnCelebration()
    try app.view(SessionAddress(week: 1, day: 1))
    _ = try app.makeCurrent()

    _ = try app.requestMoveOnCelebration()
    let report = try app.dismissMoveOnCelebration()

    #expect(report.returnedToBlockGrid == false)
    #expect(report.snapshot.currentSession == SessionAddress(week: 1, day: 2))
}
