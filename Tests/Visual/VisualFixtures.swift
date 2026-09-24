@testable import WorkoutTracker

@MainActor
enum VisualFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

actor VisualNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
