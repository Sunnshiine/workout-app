import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func aSetLoggedOnTheReplacementFixtureSheetStaysLoggedAfterTheNextSync() async throws {
    let app = try await BootedFixture.boot([]).app
    _ = try await app.selectSpreadsheet(
        id: WorkoutFixtureScenarios.replacementSheetId,
        title: "Replacement Training Log"
    )
    expectShowsOnlySessionsOfItsBlock(app.workout)

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
    expectShowsOnlySessionsOfItsBlock(app.workout)
    #expect(synced.syncOutcome.status == .clear)
    #expect(synced.pendingWriteCount == 0)
    let squat = try #require(try app.session(SessionAddress(week: 1, day: 1)).exercises.first)
    #expect(squat.name == "Replacement Squat")
    #expect(squat.sets.map(\.state) == ["logged"])
    #expect(squat.sets.map(\.setLog) == ["185x5@8"])
}

@MainActor
@Test func syncFlushesTheQueuedWriteIntoTheFixtureSheetAndReloadsIt() async throws {
    let app = try await BootedFixture.boot(["-UITEST_PENDING_WRITE"]).app
    #expect(try app.snapshot().pendingWriteCount == 1)

    let synced = try await app.sync()
    expectShowsOnlySessionsOfItsBlock(app.workout)

    #expect(synced.syncOutcome.status == .clear)
    #expect(synced.pendingWriteCount == 0)
    // The Coach Note holds the RDL's own Notes cell, so its Set Logs go to the visible row under it.
    #expect(try await app.sheet(tab: nil).cells["K19"] == "Start w/ 10 sec hold, proceed to rep range.")
    #expect(try await app.sheet(tab: nil).cells["K20"] == "225x8@8")
    let rdl = try #require(try app.session(SessionAddress(week: 1, day: 1)).exercises.first { $0.name == "2-3:1:0 BB RDL" })
    #expect(rdl.sets.map(\.state) == ["logged", "pending"])
    #expect(rdl.sets.map(\.setLog) == ["225x8@8", nil])
}

@MainActor
@Test func aLogOnTheFixtureSheetFlushesIntoItsWorkbook() async throws {
    let app = try await BootedFixture.boot(["-UITEST_FULL_BLOCK"]).app

    _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "235x5@6")
    let flush = try await app.flush()

    #expect(flush.written == 1)
    #expect(flush.conflictedWrites == [])
    #expect(flush.remainingPendingWrites == 0)
    // Back Squat's first Line holds the Coach Note, so its Set Log goes to the Exercise's spare row.
    #expect(try await app.sheet(tab: nil).cells["K15"] == "Brace hard off the floor, controlled descent.")
    #expect(try await app.sheet(tab: nil).cells["K18"] == "235x5@6")
}

@MainActor
@Test func aSyncAfterTheBootKeepsTheScenariosSetLogs() async throws {
    let app = try await BootedFixture.boot(["-UITEST_OPEN_EXERCISES"]).app

    let synced = try await app.sync()

    #expect(synced.syncOutcome.status == .clear)
    for (session, log) in [("w1d1", "235x5@6"), ("w1d2", "155x5@6"), ("w1d3", "305x3@6")] {
        let lift = try #require(try app.session(try #require(SessionAddress(session))).exercises.first)
        #expect(lift.sets.map(\.state) == ["logged", "pending"], "\(session)")
        #expect(lift.sets.map(\.setLog) == [log, nil], "\(session)")
    }
}

@MainActor
@Test func theOfflineLaunchLeavesTheFixtureSheetUnreachableAfterTheBoot() async throws {
    let app = try await BootedFixture.boot(["-UITEST_OFFLINE"]).app

    await #expect(throws: ApplicationError.self) { try await app.sync() }

    #expect(try app.snapshot().syncOutcome.status == .sheetUnreachable)
}

@MainActor
@Test func aLogOnTheOfflineFixtureSheetStaysQueued() async throws {
    let app = try await BootedFixture.boot(["-UITEST_FULL_BLOCK", "-UITEST_OFFLINE"]).app

    _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "235x5@6")
    let flush = try await app.flush()

    #expect(flush.remainingPendingWrites == 1)
    #expect(flush.syncOutcome == SyncOutcomeSnapshot(.writesQueued(1)))
}
