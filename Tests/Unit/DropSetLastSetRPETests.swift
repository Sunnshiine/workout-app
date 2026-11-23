import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)

/// The top Set of `HB SQ` 1x6 on row 15, with the Drop on row 17 written as an unnamed Drop line
/// the app adds, or as a named Drop row, which is an Exercise of its own, and `Next Lift` on row 22.
private let namedDrop: [String: String] = ["C17": "HB SQ Drop", "F17": "8", "H17": "Drop 20%"]
private let unnamedDrop: [String: String] = ["F17": "8", "H17": "Drop 20%"]

@MainActor
private func makeApp(drop: [String: String]) async throws -> (app: WorkoutApplication, sheet: LocalWorkbookSheetsClient) {
    var workbook = WorkbookScenario.freshBlock.workbook()
    var tab = try #require(workbook.tabs["Block 27"])
    tab.cells = tab.cells.filter { key, _ in key.wholeMatch(of: /[C-K](1[5-9]|2\d|3[0-6])/) == nil }
    let exercises = ["C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"]
    tab.cells.merge(exercises.merging(drop) { _, new in new }) { _, new in new }
    workbook.tabs["Block 27"] = tab
    let sheet = LocalWorkbookSheetsClient(workbook: workbook, failedUpdateRequestNumbers: [])
    let app = try WorkoutApplication(environment: .inMemory(sheets: sheet, now: { frozenNow }))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return (app, sheet)
}

@MainActor
private func lastSetRPE(after app: WorkoutApplication) async throws -> String? {
    let flush = try await app.flush()
    #expect(flush.conflictedWrites == [])
    return try await app.sheet(tab: nil).cells["I15"]
}

/// Last Set RPE mirrors the last Set the coach counted, as the app wrote it before it read Drop
/// lines. A Drop Set it adds after them never writes it. Provisional call, recorded in #1247.
@MainActor
@Test func lastSetRPEStaysOnTheTopSetWhenTheDropIsLogged() async throws {
    let (app, _) = try await makeApp(drop: unnamedDrop)
    let sets = try app.session(SessionAddress(week: 1, day: 1)).exercises[0].sets
    #expect(sets.map(\.prescribedLoad) == ["RPE8", "Drop 20%"])

    _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "175x6@8")
    #expect(try await lastSetRPE(after: app) == "8")

    _ = try app.log(try #require(SetAddress("w1d1.e0.s1")), setLog: "140x8@9")
    #expect(try await lastSetRPE(after: app) == "8")

    _ = try app.skip(try #require(SetAddress("w1d1.e0.s1")))
    #expect(try await lastSetRPE(after: app) == "8")

    _ = try app.deleteLog(try #require(SetAddress("w1d1.e0.s0")))
    #expect(try await lastSetRPE(after: app) == nil)
}

/// A named Drop row is an Exercise of its own, so its log writes its own Last Set RPE, as before the
/// app read Drop lines, including on a Sheet that already holds the top Set's.
@MainActor
@Test(arguments: [[:], ["K15": "175x6@8", "I15": "8"]])
func aNamedDropRowsLogWritesItsOwnLastSetRPE(written: [String: String]) async throws {
    let (app, _) = try await makeApp(drop: namedDrop.merging(written) { _, new in new })

    if written.isEmpty {
        _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "175x6@8")
    }
    _ = try app.log(try #require(SetAddress("w1d1.e1.s0")), setLog: "140x8@9")
    #expect(try await lastSetRPE(after: app) == "8")
    #expect(try await app.sheet(tab: nil).cells["I17"] == "9")
    #expect(try await app.sheet(tab: nil).cells["K17"] == "140x8@9")
}
