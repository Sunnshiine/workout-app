import ArgumentParser
import WorkoutTracker

struct CellReport: Encodable {
    let tab: String
    let cell: String
    let value: String
}

struct SheetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sheet",
        abstract: "Read a workbook tab through the SheetsClient: every non-empty cell, or one cell with --cell."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Option(help: "Tab name. Defaults to the cached Block's tab.")
    var tab: String?

    @Option(help: "One A1 cell, such as K15. An empty cell prints \"\".")
    var cell: String?

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        if let cell {
            try await Output.run {
                let reference = cell.uppercased()
                guard reference.wholeMatch(of: /[A-Z]+[1-9][0-9]*/) != nil else { throw CLIError.invalidCell(cell) }
                let snapshot = try await home.open().sheet(tab: tab)
                return CellReport(tab: snapshot.tab, cell: reference, value: snapshot.cells[reference] ?? "")
            }
        } else {
            try await Output.run { try await home.open().sheet(tab: tab) }
        }
    }
}
