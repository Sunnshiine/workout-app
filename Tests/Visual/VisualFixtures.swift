@testable import WorkoutTracker

/// Holds every scenario a visual test builds for the rest of the run, so its model container
/// outlives the views rendered from it.
@MainActor
enum VisualFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

/// A Sheets client that answers every call with nothing, for a view that needs one in its environment.
actor VisualNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
