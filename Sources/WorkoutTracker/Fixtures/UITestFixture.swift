#if DEBUG
    import Foundation
    import SwiftData

    /// Boots the app into a deterministic, populated `SessionView` for unattended UI verification.
    ///
    /// Activated by launching with the `-UITEST_FIXTURE` argument. Uses an in-memory store and a
    /// faked sign-in so it never touches real data, Google auth, or the network — the Ralph loop
    /// can screenshot a known screen without clearing the OAuth onboarding wall.
    enum UITestFixture {
        /// The launch configuration this process was started with.
        static let launch = UITestLaunch(arguments: ProcessInfo.processInfo.arguments)

        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_FIXTURE")
        }

        static let disablesAnimations = isEnabled && launch.disablesAnimations

        static func makeSheetsClient() -> any SheetsClient {
            FixtureSheetsClient(
                slowsSync: launch.slowsSync,
                replacementSheet: LocalWorkbookSheetsClient(
                    spreadsheetId: WorkoutFixtureScenarios.replacementSheetId,
                    tabs: [WorkoutFixtureScenarios.blockTab: WorkoutFixtureScenarios.replacementSheetGrid]
                )
            )
        }

        @MainActor
        static func seed(into context: ModelContext, launch: UITestLaunch) throws {
            context.insert(block(for: launch.scenario))
            for entry in WorkoutFixtureScenarios.backSquatHistory() + WorkoutFixtureScenarios.benchPressHistory() {
                context.insert(entry)
            }
            if launch.startsWithPendingWrite {
                context.insert(WorkoutFixtureScenarios.queuedWrite())
            }
            try context.save()
        }

        /// One Block factory per scenario. A table has no compiler exhaustiveness check, so
        /// `everyScenarioSeedsItsOwnFixtureBlock` in `Tests/Unit/UITestFixtureBlockTests.swift`
        /// is what keeps a new scenario from reaching `seed` without a row.
        @MainActor
        private static let blocks: [UITestLaunch.Scenario: @MainActor () -> Block] = [
            .perfectMoveOnCelebration: WorkoutFixtureScenarios.perfectMoveOnCelebrationBlock,
            .completedOpenExercises: WorkoutFixtureScenarios.completedSessionWithOpenExercisesBlock,
            .openExercises: WorkoutFixtureScenarios.openExercisesBlock,
            .longSession: WorkoutFixtureScenarios.longSessionBlock,
            .fullBlock: WorkoutFixtureScenarios.uiLaunchBlock,
            .partialUpload: WorkoutFixtureScenarios.partiallyUploadedBlock
        ]

        @MainActor
        static func block(for scenario: UITestLaunch.Scenario) -> Block {
            guard let block = blocks[scenario] else {
                preconditionFailure("No fixture Block for \(scenario)")
            }
            return block()
        }
    }

    private struct FixtureSheetsClient: SheetsClient {
        let slowsSync: Bool
        let replacementSheet: LocalWorkbookSheetsClient

        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            if slowsSync {
                try await Task.sleep(for: .seconds(20))
            }
            return ["Block 27"]
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
            return try await replacementSheet.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName)
        }

        func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
            try await updateCells(spreadsheetId: spreadsheetId, updates: [SheetValueRangeUpdate(range: range, values: values)])
        }

        func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
            guard spreadsheetId == WorkoutFixtureScenarios.replacementSheetId else { return }
            try await replacementSheet.updateCells(spreadsheetId: spreadsheetId, updates: updates)
        }
    }
#endif
