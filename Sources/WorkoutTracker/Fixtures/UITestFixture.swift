#if DEBUG
    import Foundation
    import SwiftData

    /// Boots the app into a deterministic, populated `SessionView` for unattended UI verification.
    ///
    /// Activated by launching with `LaunchFlag.fixture`. An in-memory store and a faked sign-in keep
    /// it off real data, Google auth, and the network, and past the OAuth onboarding wall.
    enum UITestFixture {
        /// The launch configuration this process was started with.
        static let launch = UITestLaunch(arguments: ProcessInfo.processInfo.arguments)

        static var isEnabled: Bool { launch.runsOnFixture }

        static let disablesAnimations = isEnabled && launch.disablesAnimations

        static func makeSheetsClient(launch: UITestLaunch) -> any SheetsClient {
            var sheets = [
                WorkoutFixtureScenarios.replacementSheetId: LocalWorkbookSheetsClient(
                    spreadsheetId: WorkoutFixtureScenarios.replacementSheetId,
                    tabs: [WorkoutFixtureScenarios.blockTab: WorkoutFixtureScenarios.replacementSheetGrid]
                )
            ]
            if launch.startsWithPendingWrite {
                sheets[WorkoutFixtureScenarios.sheetId] = LocalWorkbookSheetsClient(workbook: WorkoutFixtureScenarios.queuedWriteSheet)
            }
            return FixtureSheetsClient(slowsSync: launch.slowsSync, sheets: sheets)
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

        /// One Block factory per scenario. `.partialUpload` parses its workbook the way a sync does;
        /// the rest still hand-build a graph until their slice of #571 lands. A table has no
        /// compiler exhaustiveness check, so `everyScenarioSeedsItsOwnFixtureBlock` in
        /// `Tests/Unit/UITestFixtureBlockTests.swift` is what keeps a new scenario from reaching
        /// `seed` without a row.
        @MainActor
        private static let blocks: [UITestLaunch.Scenario: @MainActor () -> Block] = [
            .perfectMoveOnCelebration: WorkoutFixtureScenarios.perfectMoveOnCelebrationBlock,
            .completedOpenExercises: WorkoutFixtureScenarios.completedSessionWithOpenExercisesBlock,
            .openExercises: WorkoutFixtureScenarios.openExercisesBlock,
            .longSession: WorkoutFixtureScenarios.longSessionBlock,
            .fullBlock: WorkoutFixtureScenarios.uiLaunchBlock,
            .partialUpload: WorkbookScenario.partialUpload.block
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
        let sheets: [String: LocalWorkbookSheetsClient]

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
            guard let sheet = sheets[spreadsheetId] else {
                throw SheetsError.malformedResponse
            }
            return try await sheet.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName)
        }

        func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
            guard let sheet = sheets[spreadsheetId] else {
                throw SheetsError.malformedResponse
            }
            try await sheet.write(cells, spreadsheetId: spreadsheetId)
        }
    }
#endif
