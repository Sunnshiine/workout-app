#if DEBUG
    import Foundation
    import SwiftData

    /// Boots the app into a deterministic, populated `SessionView` for unattended UI verification.
    ///
    /// Activated by launching with `LaunchFlag.fixture`. An in-memory store and a faked sign-in keep
    /// it off real data, Google auth, and the network, and past the OAuth onboarding wall. The
    /// fixture's spreadsheets are local workbooks in one `LocalDrive`, and `boot` fills the store the
    /// way a phone's first sync does.
    enum UITestFixture {
        /// The launch configuration this process was started with.
        static let launch = UITestLaunch(arguments: ProcessInfo.processInfo.arguments)

        static var isEnabled: Bool { launch.runsOnFixture }

        static let disablesAnimations = isEnabled && launch.disablesAnimations

        /// The one drive this process's fixture application and its sheet pickers share, so a
        /// picker lists the spreadsheets the application syncs and both meet the same faults.
        @MainActor static let sheets = makeSheets(launch: launch)

        /// Where a launch scenario's Block comes from.
        enum Source {
            /// Parsed from the workbook by the boot sync, as a phone's first sync parses the Sheet.
            case workbook(WorkbookScenario)
            /// A Block graph built in Swift and inserted straight into the store, with no Sheet
            /// behind it. #970 converts the last of these to workbooks and deletes this case.
            case handBuilt(@MainActor () -> Block)
        }

        /// One source per scenario. A table has no compiler exhaustiveness check, so
        /// `everyScenarioSeedsItsOwnFixtureBlock` in `Tests/Unit/UITestFixtureBlockTests.swift` is
        /// what keeps a new scenario from reaching `boot` without a row.
        @MainActor
        private static let sources: [UITestLaunch.Scenario: Source] = [
            .perfectMoveOnCelebration: .handBuilt(WorkoutFixtureScenarios.perfectMoveOnCelebrationBlock),
            .completedOpenExercises: .handBuilt(WorkoutFixtureScenarios.completedSessionWithOpenExercisesBlock),
            .openExercises: .handBuilt(WorkoutFixtureScenarios.openExercisesBlock),
            .longSession: .handBuilt(WorkoutFixtureScenarios.longSessionBlock),
            .fullBlock: .workbook(.fullBlock),
            .partialUpload: .workbook(.partialUpload)
        ]

        @MainActor
        static func source(for scenario: UITestLaunch.Scenario) -> Source {
            guard let source = sources[scenario] else {
                preconditionFailure("No fixture Block for \(scenario)")
            }
            return source
        }

        /// The REPLACEMENT spreadsheet, and the scenario's workbook as FIXTURE when it has one. A
        /// hand-built scenario has no Sheet, so FIXTURE is absent and every read of it fails.
        @MainActor
        static func makeSheets(launch: UITestLaunch) -> LocalDrive {
            var workbooks = [WorkoutFixtureScenarios.replacementWorkbook]
            if case .workbook(let scenario) = source(for: launch.scenario) {
                workbooks.append(scenario.workbook())
            }
            return LocalDrive(workbooks)
        }

        /// The set the pending-write launch logs at boot and leaves unflushed: Week 1 Day 1's BB RDL,
        /// whose log a flush writes to the visible row under its Coach Note.
        static let pendingWriteSet = SetAddress(exercise: ExerciseAddress(session: SessionAddress(week: 1, day: 1), order: 1), index: 0)
        static let pendingWriteLog = "225x8@8"

        enum BootFailure: Error, CustomStringConvertible {
            case syncFailed(SyncOutcome)
            case pendingWriteNeedsAWorkbook(UITestLaunch.Scenario)

            var description: String {
                switch self {
                case .syncFailed(let outcome):
                    "The fixture's boot sync failed: \(outcome)"
                case .pendingWriteNeedsAWorkbook(let scenario):
                    "\(LaunchFlag.pendingWrite.argument) logs into the fixture Sheet, and \(scenario) has none"
                }
            }
        }

        /// Brings a fresh fixture application to the state `launch` names, through the calls a
        /// phone makes: a sync of the fixture Sheet, the Exercise History its earlier fills left, and
        /// for a pending-write launch a log that was never flushed. Then the drive's faults are
        /// armed: unless a pending write wants a sync to land, FIXTURE disconnects, so a log stays
        /// queued as it always has in the fixture, and a slow-sync launch holds every later tab
        /// list. The faults wait for the boot, so it never stalls on them.
        @MainActor
        static func boot(_ app: WorkoutApplication, launch: UITestLaunch, sheets: LocalDrive) async throws {
            app.settings.setAppearance(try launch.appearance)
            app.settings.isSignedIn = !launch.signsInLate
            let scenarioSource = source(for: launch.scenario)
            try await load(scenarioSource, into: app)
            try app.lastPerformed.ingest(WorkoutFixtureScenarios.backSquatHistory() + WorkoutFixtureScenarios.benchPressHistory())
            app.workout.reload()
            try await queueOrDisconnect(scenarioSource, app: app, launch: launch, sheets: sheets)
            if launch.slowsSync {
                await sheets.holdTabListings(for: .seconds(20))
            }
            // Onboarding leaves the spreadsheet unset so the app lands on the sheet picker, while
            // the synced (stale) Block stays in the store to prove it is never shown for the newly
            // selected sheet.
            if !launch.startsInOnboarding {
                app.settings.setSpreadsheet(id: WorkoutFixtureScenarios.sheetId, title: WorkbookScenario.title)
            }
            present(launch, on: app.workout)
        }

        @MainActor
        private static func load(_ source: Source, into app: WorkoutApplication) async throws {
            switch source {
            case .workbook:
                guard await app.sync.sync(spreadsheetId: WorkoutFixtureScenarios.sheetId) else {
                    throw BootFailure.syncFailed(app.sync.outcome)
                }
            case .handBuilt(let block):
                let context = app.container.mainContext
                context.insert(block())
                try context.save()
            }
        }

        /// A pending-write launch logs and leaves FIXTURE reachable for the sync that lands it;
        /// every other launch disconnects FIXTURE.
        @MainActor
        private static func queueOrDisconnect(
            _ source: Source,
            app: WorkoutApplication,
            launch: UITestLaunch,
            sheets: LocalDrive
        ) async throws {
            guard launch.startsWithPendingWrite else {
                await sheets.disconnect(WorkoutFixtureScenarios.sheetId)
                return
            }
            guard case .workbook = source else {
                throw BootFailure.pendingWriteNeedsAWorkbook(launch.scenario)
            }
            _ = try app.log(pendingWriteSet, setLog: pendingWriteLog)
        }

        @MainActor
        private static func present(_ launch: UITestLaunch, on workout: WorkoutStore) {
            if launch.startsWithCurrentSessionOverride {
                workout.show(SessionAddress(week: 1, day: 3))
                workout.makeViewedSessionCurrent()
            }
            if launch.startsWithMoveOnCelebration || launch.startsWithPerfectMoveOnCelebration {
                workout.requestMoveOnCelebration()
            }
            if launch.startsInBlockOverview {
                workout.requestBlockOverviewPresentation()
            }
        }
    }
#endif
