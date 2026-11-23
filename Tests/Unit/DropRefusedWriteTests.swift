import Foundation
import Testing

@testable import WorkoutTracker

/// M0: the top Set's Notes hold a Coach Note and the next Exercise starts on the row below, so
/// Set 1 has no row of its own. Main refuses this log the same way.
@MainActor
private func makeApp() async throws -> WorkoutApplication {
    var workbook = WorkbookScenario.freshBlock.workbook()
    var tab = try #require(workbook.tabs["Block 27"])
    tab.cells = tab.cells.filter { key, _ in key.wholeMatch(of: /[C-K](1[5-9]|2\d|3[0-6])/) == nil }
    tab.cells.merge([
        "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace",
        "C16": "Next Lift", "D16": "2", "F16": "10", "H16": "RPE8"
    ]) { _, new in new }
    workbook.tabs["Block 27"] = tab
    let sheet = LocalWorkbookSheetsClient(workbook: workbook, failedUpdateRequestNumbers: [])
    let app = try WorkoutApplication(environment: .inMemory(sheets: sheet, now: { Date(timeIntervalSince1970: 1_780_000_000) }))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return app
}

/// A log with no row to land on is refused out loud and kept on the phone, never written over
/// the next Exercise's row and never dropped. The banner is the only mark: the next flush clears
/// it, and a Set that never reached the Sheet still reads Logged (#1247).
@MainActor
@Test func aLogWithNoRowToLandOnIsRefusedOutLoudAndKeptOnThePhone() async throws {
    let app = try await makeApp()
    _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "175x6@8")

    let flush = try await app.flush()
    #expect(flush.written == 0)
    let banner = try #require(SyncStatusBannerPresentation(outcome: app.sync.outcome, isSyncing: false))
    #expect(banner.text == "The sheet changed, so your log was not written")
    #expect(banner.detail?.contains("Set 1 for HB SQ cannot be written") == true)
    #expect(!banner.isBrief)
    let cells = try await app.sheet(tab: nil).cells
    #expect(cells["K15"] == "Brace")
    #expect(cells["K16"] == nil)
    #expect(cells["I15"] == nil)

    let report = try await app.sync()
    #expect(report.conflictedWrites.count == 2)
    let set = try app.session(SessionAddress(week: 1, day: 1)).exercises[0].sets[0]
    #expect("\(set.state)" == "logged")
    #expect(set.setLog == "175x6@8")
}
