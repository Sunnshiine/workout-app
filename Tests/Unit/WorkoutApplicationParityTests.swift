import Foundation
import Testing

@testable import WorkoutTracker

private struct PendingWriteRow: Equatable {
    let blockTab: String
    let week: Int
    let day: Int
    let exerciseName: String
    let setIndex: Int
    let column: PendingWriteColumn
    let operation: PendingWriteOperation
    let valueToWrite: String?
    let expectedCurrentValue: String

    @MainActor
    init(_ write: PendingWrite) {
        blockTab = write.blockTab
        week = write.week
        day = write.day
        exerciseName = write.exerciseName
        setIndex = write.setIndex
        column = write.column
        operation = write.operation
        valueToWrite = write.valueToWrite
        expectedCurrentValue = write.expectedCurrentValue
    }
}

@MainActor
private func makeApp() async throws -> WorkoutApplication {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
    return app
}

@MainActor
private func pendingRows(in app: WorkoutApplication) throws -> [PendingWriteRow] {
    try app.sync.fetchPendingWriteRecords().map(PendingWriteRow.init)
}

@MainActor
@Test func facadeLogMatchesTheSessionCoordinatorLogPath() async throws {
    let stageApp = try await makeApp()
    let facadeApp = try await makeApp()
    let setLog = try #require(SetLog(formatted: "200x5@9"))

    let stageSet = try #require(
        stageApp.workout.block?.weeks.first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == 1 }?
            .exercises.first { $0.order == 0 }?
            .sets.first { $0.index == 2 }
    )
    let coordinator = SessionCoordinator(session: stageSet.exercise?.session, logging: stageApp.workout)
    coordinator.log(stageSet, as: setLog)

    let report = try facadeApp.log(try #require(SetAddress("w1d1.e0.s2")), setLog: "200x5@9")

    let stageRows = try pendingRows(in: stageApp)
    #expect(stageRows.count == 2)
    #expect(stageRows == (try pendingRows(in: facadeApp)))
    #expect(report.pendingWriteCount == 2)
    #expect(stageSet.loggedAt == report.set.loggedAt)

    _ = try await stageApp.flush()
    _ = try await facadeApp.flush()

    let stageSheet = try await stageApp.sheet(tab: nil)
    let facadeSheet = try await facadeApp.sheet(tab: nil)
    #expect(stageSheet == facadeSheet)
    #expect(facadeSheet.cells["K15"] == ", , 200x5@9")
    #expect(facadeSheet.cells["I15"] == "9")
    #expect(try stageApp.snapshot() == facadeApp.snapshot())
}
