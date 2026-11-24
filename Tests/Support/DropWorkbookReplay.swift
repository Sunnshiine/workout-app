import Foundation
import Testing

@testable import WorkoutTracker

/// One step of a Drop workbook: the athlete's `log`, `deleteLog`, `flush` and `sync`, or a coach edit to the Sheet.
enum DropWorkbookStep: Sendable {
    case log(String, String)
    case deleteLog(String)
    case flush
    case sync
    case edit([String: String])
    case hide([Int])
    case unhide([Int])
}

/// A Week 1 Day 1 body for `HB SQ` and the Exercises below it, the steps run on it, and what main's
/// `workout` CLI left after the same steps: the body cells, and each Set it read, as
/// `e<Exercise>.s<Set> <Prescribed Load> <state> <Set Log>`. Rows are 1-based Sheet rows.
struct DropWorkbook: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let cells: [String: String]
    let hidden: [Int]
    let steps: [DropWorkbookStep]
    let mainCells: [String: String]
    let mainSets: [String]
}

/// The body cells after the steps, and each Set the app reads, as `DropWorkbook.mainSets` writes them.
struct ReplayedDropWorkbook {
    let cells: [String: String]
    let sets: [String]
}

/// Runs `workbook` on a file-backed Sheet, as the CLI does, so a coach edit between two steps is
/// read by the next one. A step that fails, as a refused log does, leaves the Sheet as it was.
@MainActor
func replayed(_ workbook: DropWorkbook) async throws -> ReplayedDropWorkbook {
    let url = FileManager.default.temporaryDirectory.appending(path: "drop-workbook-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var seeded = WorkbookScenario.freshBlock.workbook()
    var tab = try #require(seeded.tabs["Block 27"])
    tab.cells = tab.cells.filter { key, _ in !isBodyCell(key) }.merging(workbook.cells) { _, new in new }
    tab.hiddenRows = Dictionary(uniqueKeysWithValues: workbook.hidden.map { ($0, SheetRowVisibility(hiddenByUser: true)) })
    seeded.tabs["Block 27"] = tab
    try seeded.write(to: url)

    let sheet = try LocalWorkbookSheetsClient(file: url)
    let app = try WorkoutApplication(environment: .inMemory(sheets: sheet, now: { Date(timeIntervalSince1970: 1_780_000_000) }))
    _ = try await app.selectSpreadsheet(id: seeded.spreadsheetId, title: seeded.title)
    for step in workbook.steps {
        try await run(step, app: app, url: url)
    }
    let cells = try #require(LocalWorkbook.load(from: url).tabs["Block 27"]).cells
    let sets = try app.session(SessionAddress(week: 1, day: 1)).exercises.flatMap { exercise in
        exercise.sets.map { "e\(exercise.order).s\($0.index) \($0.prescribedLoad) \($0.state) \($0.setLog ?? $0.unstructuredSetLog ?? "")" }
    }
    return ReplayedDropWorkbook(cells: cells.filter { key, value in isBodyCell(key) && !value.isEmpty }, sets: sets)
}

@MainActor
private func run(_ step: DropWorkbookStep, app: WorkoutApplication, url: URL) async throws {
    switch step {
    case .log(let address, let setLog):
        _ = try? app.log(try #require(SetAddress(address)), setLog: setLog)
    case .deleteLog(let address):
        _ = try? app.deleteLog(try #require(SetAddress(address)))
    case .flush:
        _ = try? await app.flush()
    case .sync:
        _ = try? await app.sync()
    case .edit(let cells):
        try editTab(at: url) { $0.cells.merge(cells) { _, new in new } }
    case .hide(let rows):
        try editTab(at: url) { tab in for row in rows { tab.hiddenRows[row] = SheetRowVisibility(hiddenByUser: true) } }
    case .unhide(let rows):
        try editTab(at: url) { tab in for row in rows { tab.hiddenRows[row] = nil } }
    }
}

private func editTab(at url: URL, _ change: (inout LocalWorkbook.Tab) -> Void) throws {
    var workbook = try LocalWorkbook.load(from: url)
    var tab = try #require(workbook.tabs["Block 27"])
    change(&tab)
    workbook.tabs["Block 27"] = tab
    try workbook.write(to: url)
}

private func isBodyCell(_ key: String) -> Bool {
    key.wholeMatch(of: /[C-K](1[5-9]|2\d|3[0-6])/) != nil
}
