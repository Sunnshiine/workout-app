#if DEBUG
    import Foundation

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

        /// The REPLACEMENT spreadsheet, and the scenario's workbook as FIXTURE.
        @MainActor
        static func makeSheets(launch: UITestLaunch) -> LocalDrive {
            LocalDrive([WorkoutFixtureScenarios.replacementWorkbook, launch.scenario.workbook()])
        }

        /// The set the pending-write launch logs at boot and leaves unflushed: Week 1 Day 1's BB RDL,
        /// whose log a flush writes to the visible row under its Coach Note.
        static let pendingWriteSet = SetAddress(exercise: ExerciseAddress(session: SessionAddress(week: 1, day: 1), order: 1), index: 0)
        static let pendingWriteLog = "225x8@8"

        struct BootSyncFailed: Error, CustomStringConvertible {
            let outcome: SyncOutcome

            var description: String { "The fixture's boot sync failed: \(outcome)" }
        }

        /// Brings a fresh fixture application to the state `launch` names, through the calls a
        /// phone makes: a sync of the fixture Sheet, the Exercise History its earlier fills left, and
        /// for a pending-write launch a log that was never flushed. Then the faults the launch asks
        /// for are armed: an offline launch disconnects FIXTURE, so a log stays queued, and a
        /// slow-sync launch holds every later tab list. The faults wait for the boot, so it never
        /// stalls on them.
        @MainActor
        static func boot(_ app: WorkoutApplication, launch: UITestLaunch, sheets: LocalDrive) async throws {
            try launch.checkFlags()
            app.settings.setAppearance(try launch.appearance)
            // A late sign-in leaves the restore running, as a device does, until the launch task ends it.
            if !launch.signsInLate {
                app.settings.isSignedIn = true
            }
            try await syncFixtureSheet(into: app)
            try app.lastPerformed.ingest(WorkoutFixtureScenarios.backSquatHistory() + WorkoutFixtureScenarios.benchPressHistory())
            app.workout.reload()
            if launch.startsWithPendingWrite {
                _ = try app.log(pendingWriteSet, setLog: pendingWriteLog)
            }
            if launch.startsOffline {
                await sheets.disconnect(WorkoutFixtureScenarios.sheetId)
            }
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

        /// Syncs the scenario's workbook, which the drive already holds as FIXTURE.
        @MainActor
        private static func syncFixtureSheet(into app: WorkoutApplication) async throws {
            guard await app.sync.sync(spreadsheetId: WorkoutFixtureScenarios.sheetId) else {
                throw BootSyncFailed(outcome: app.sync.outcome)
            }
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
