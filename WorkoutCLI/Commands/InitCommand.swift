import ArgumentParser
import Foundation
import WorkoutTracker

struct InitReport: Encodable {
    let home: String
    let scenario: String
    let spreadsheetId: String
    let spreadsheetTitle: String?
    let block: BlockSummary?
    let currentSession: SessionAddress?
}

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Reset the home, seed the workbook from a scenario, select it, and sync. Running it twice gives the same state."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Option(help: "Seed workbook: \(WorkbookScenario.allCases.map(\.rawValue).joined(separator: ", ")).")
    var scenario: WorkbookScenario = .freshBlock

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            let workbook = scenario.workbook()
            let manifest = try home.reset(scenario: scenario, workbook: workbook)
            let app = try home.open()
            let snapshot = try await app.selectSpreadsheet(id: manifest.spreadsheetId, title: workbook.title)
            return InitReport(
                home: home.url.path,
                scenario: manifest.scenario,
                spreadsheetId: manifest.spreadsheetId,
                spreadsheetTitle: snapshot.spreadsheetTitle,
                block: snapshot.block,
                currentSession: snapshot.currentSession
            )
        }
    }
}

extension WorkbookScenario: ExpressibleByArgument {}
