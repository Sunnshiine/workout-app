import Testing

@testable import WorkoutTracker

@MainActor
@Test func aSetLoggedOnTheReplacementFixtureSheetStaysLoggedAfterTheNextSync() async throws {
    let app = try WorkoutApplication(environment: .uiTestFixture())
    _ = try await app.selectSpreadsheet(
        id: WorkoutFixtureScenarios.replacementSheetId,
        title: "Replacement Training Log"
    )

    _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "185x5@8")
    let flush = try await app.flush()

    #expect(
        flush
            == FlushReport(
                attempted: 2,
                written: 2,
                conflictedWrites: [],
                remainingPendingWrites: 0,
                syncOutcome: SyncOutcomeSnapshot(.clear)
            )
    )

    let synced = try await app.sync()
    #expect(synced.syncOutcome.status == .clear)
    #expect(synced.pendingWriteCount == 0)
    let squat = try #require(try app.session(SessionAddress(week: 1, day: 1)).exercises.first)
    #expect(squat.name == "Replacement Squat")
    #expect(squat.sets.map(\.state) == ["logged"])
    #expect(squat.sets.map(\.setLog) == ["185x5@8"])
}
