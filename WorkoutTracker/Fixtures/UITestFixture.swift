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

        static var startsWithCompletedOpenExercises: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_COMPLETED_OPEN_EXERCISES")
        }

        static var startsWithLongSession: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_LONG_SESSION")
        }

        static var startsInDeveloperTools: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_DEVELOPER_TOOLS")
        }

        static var startsInSettings: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_SETTINGS")
        }

        /// Boots signed-in but with **no** spreadsheet selected, so the app shows onboarding's sheet
        /// picker. Combined with the seeded (stale) Block this exercises the onboarding selection
        /// path that previously bypassed the safe Settings switch flow.
        static var startsInOnboarding: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_ONBOARDING")
        }

        static var startsWithCurrentSessionOverride: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_CURRENT_SESSION_OVERRIDE")
        }

        static var startsInSession: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_SESSION")
        }

        static var startsWithMoveOnCelebration: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_MOVE_ON_CELEBRATION")
        }

        static var startsWithPerfectMoveOnCelebration: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_PERFECT_MOVE_ON_CELEBRATION")
        }

        static var startsInBlockOverview: Bool {
            !startsInSession && !startsInDeveloperTools && !startsInSettings && !startsInOnboarding
        }

        static var startsWithFullBlock: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_FULL_BLOCK")
        }

        static var appearanceOverride: AppearancePreference? {
            appearanceOverride(from: ProcessInfo.processInfo.arguments)
        }

        static func appearanceOverride(from arguments: [String]) -> AppearancePreference? {
            guard
                let argumentIndex = arguments.firstIndex(of: "-UITEST_APPEARANCE"),
                arguments.indices.contains(arguments.index(after: argumentIndex))
            else {
                return nil
            }
            return AppearancePreference(rawValue: arguments[arguments.index(after: argumentIndex)])
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
                WriteTargetAuditEntry.self,
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
                startsWithPerfectMoveOnCelebration
                ? WorkoutFixtureScenarios.perfectMoveOnCelebrationBlock()
                : startsWithCompletedOpenExercises
                ? WorkoutFixtureScenarios.completedSessionWithOpenExercisesBlock()
                : startsWithOpenExercises
                ? WorkoutFixtureScenarios.openExercisesBlock()
                : startsWithLongSession
                    ? WorkoutFixtureScenarios.longSessionBlock()
                    : startsWithFullBlock
                        ? WorkoutFixtureScenarios.uiLaunchBlock()
                        : WorkoutFixtureScenarios.partiallyUploadedBlock()
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

        func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
            guard spreadsheetId == WorkoutFixtureScenarios.replacementSheetId else {
                throw SheetsError.malformedResponse
            }

            return SheetSnapshot(
                values: gridFromA1(
                    [
                        "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
                        "C13": "5/1/2026",
                        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                        "C15": "Replacement Squat", "D15": "1", "F15": "5", "H15": "RPE8"
                    ],
                    rows: 20,
                    cols: 60
                )
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
