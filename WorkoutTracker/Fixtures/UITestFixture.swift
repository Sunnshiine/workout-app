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
            context.insert(WorkoutFixtureScenarios.uiLaunchBlock())
            context.insert(WorkoutFixtureScenarios.lastPerformedBackSquat())
            // swiftlint:disable:next force_try
            try! context.save()
        }
    }

    private struct FixtureSheetsClient: SheetsClient {
        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            ["Block 27"]
        }

        func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
            throw SheetsError.malformedResponse
        }

        func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
    }
#endif
