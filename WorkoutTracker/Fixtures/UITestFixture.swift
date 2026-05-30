#if DEBUG
    import Foundation
    import SwiftData

    /// Boots the app into a deterministic, populated `SessionView` for unattended UI verification.
    ///
    /// Activated by launching with the `-UITEST_FIXTURE` argument. Uses an in-memory store and a
    /// faked sign-in so it never touches real data, Google auth, or the network — the Ralph loop
    /// can screenshot a known screen without clearing the OAuth onboarding wall.
    enum UITestFixture {
        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_FIXTURE")
        }

        static var startsWithPendingWrite: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_PENDING_WRITE")
        }

        static var startsWithOpenExercises: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_OPEN_EXERCISES")
        }

        static var startsInDeveloperTools: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_DEVELOPER_TOOLS")
        }

        private static let defaultsSuiteName = "WorkoutTracker.UITestFixture"

        /// An in-memory container seeded with one sample Block.
        @MainActor
        static func makeContainer() -> ModelContainer {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            let container = try! ModelContainer(
                for: Block.self,
                PendingWrite.self,
                LastPerformedEntry.self,
                configurations: config
            )
            seed(into: container.mainContext)
            return container
        }

        static func makeDefaults() -> UserDefaults {
            let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            return defaults
        }

        static func makeSheetsClient() -> any SheetsClient {
            FixtureSheetsClient()
        }

        @MainActor
        private static func seed(into context: ModelContext) {
            let block =
                startsWithOpenExercises
                ? WorkoutFixtureScenarios.openExercisesBlock()
                : WorkoutFixtureScenarios.uiLaunchBlock()
            context.insert(block)
            context.insert(WorkoutFixtureScenarios.lastPerformedBackSquat())
            if startsWithPendingWrite {
                context.insert(WorkoutFixtureScenarios.queuedWrite())
            }
            // swiftlint:disable:next force_try
            try! context.save()
        }
    }

    private struct FixtureSheetsClient: SheetsClient {
        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            ["Block 27"]
        }

        func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
            SpreadsheetListPage(
                spreadsheets: [
                    SpreadsheetFile(
                        name: "Replacement Training Log",
                        spreadsheetId: WorkoutFixtureScenarios.replacementSheetId,
                        modifiedDate: Date(timeIntervalSinceReferenceDate: 0)
                    )
                ],
                nextPageToken: nil
            )
        }

        func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
            guard spreadsheetId == WorkoutFixtureScenarios.replacementSheetId else {
                throw SheetsError.malformedResponse
            }

            return gridFromA1(
                [
                    "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
                    "C13": "5/1/2026",
                    "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                    "C15": "Replacement Squat", "D15": "1", "F15": "5", "H15": "RPE8"
                ],
                rows: 20,
                cols: 60
            )
        }

        func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
    }

    private func gridFromA1(_ cells: [String: String], rows: Int, cols: Int) -> SheetGrid {
        var grid = SheetGrid(repeating: [String](repeating: "", count: cols), count: rows)
        for (a1, value) in cells {
            let index = a1ToIndex(a1)
            if index.row < rows, index.col < cols {
                grid[index.row][index.col] = value
            }
        }
        return grid
    }
#endif
