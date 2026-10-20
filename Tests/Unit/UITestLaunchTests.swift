import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

#if DEBUG

    @Test func launchFlagsAreOffWithoutTheirArgument() {
        let launch = UITestLaunch(arguments: ["WorkoutTracker"])

        #expect(launch.disablesAnimations == false)
        #expect(launch.disablesLiveActivities == false)
        #expect(launch.endsLiveActivities == false)
        #expect(launch.startsWithPendingWrite == false)
        #expect(launch.startsOffline == false)
        #expect(launch.slowsSync == false)
        #expect(launch.signsInLate == false)
        #expect(launch.startsInDeveloperTools == false)
        #expect(launch.startsInSettings == false)
        #expect(launch.startsInOnboarding == false)
        #expect(launch.startsWithCurrentSessionOverride == false)
        #expect(launch.startsWithMoveOnCelebration == false)
        #expect(launch.startsWithPerfectMoveOnCelebration == false)
    }

    @Test func eachLaunchFlagParsesFromItsArgument() {
        #expect(UITestLaunch(arguments: ["-UITEST_DISABLE_ANIMATIONS"]).disablesAnimations)
        #expect(UITestLaunch(arguments: ["-UITEST_DISABLE_LIVE_ACTIVITIES"]).disablesLiveActivities)
        #expect(UITestLaunch(arguments: ["-UITEST_END_LIVE_ACTIVITIES"]).endsLiveActivities)
        #expect(UITestLaunch(arguments: ["-UITEST_PENDING_WRITE"]).startsWithPendingWrite)
        #expect(UITestLaunch(arguments: ["-UITEST_OFFLINE"]).startsOffline)
        #expect(UITestLaunch(arguments: ["-UITEST_SLOW_SYNC"]).slowsSync)
        #expect(UITestLaunch(arguments: ["-UITEST_LATE_SIGN_IN"]).signsInLate)
        #expect(UITestLaunch(arguments: ["-UITEST_DEVELOPER_TOOLS"]).startsInDeveloperTools)
        #expect(UITestLaunch(arguments: ["-UITEST_SETTINGS"]).startsInSettings)
        #expect(UITestLaunch(arguments: ["-UITEST_ONBOARDING"]).startsInOnboarding)
        #expect(UITestLaunch(arguments: ["-UITEST_CURRENT_SESSION_OVERRIDE"]).startsWithCurrentSessionOverride)
        #expect(UITestLaunch(arguments: ["-UITEST_MOVE_ON_CELEBRATION"]).startsWithMoveOnCelebration)
        #expect(UITestLaunch(arguments: ["-UITEST_PERFECT_MOVE_ON_CELEBRATION"]).startsWithPerfectMoveOnCelebration)
    }

    @Test func eachScenarioFlagIsSpelledAfterItsWorkbookAndSelectsIt() {
        for (flag, scenario) in UITestLaunch.scenarioFlags {
            let spelled = LaunchFlag.prefix + scenario.rawValue.uppercased().replacingOccurrences(of: "-", with: "_")
            #expect(flag.argument == spelled, "\(scenario.rawValue)")
            #expect(UITestLaunch(arguments: [flag.argument]).scenario == scenario)
        }
        #expect(UITestLaunch(arguments: ["-UITEST_FULL_BLOCK"]).scenario == .fullBlock)
        #expect(UITestLaunch(arguments: ["-UITEST_PARTIAL_UPLOAD"]).scenario == .partialUpload)
    }

    @Test func theScenarioTableHasOneFlagPerWorkbook() {
        let flags = UITestLaunch.scenarioFlags.map(\.flag)
        let scenarios = UITestLaunch.scenarioFlags.map(\.scenario)
        #expect(Set(flags).count == flags.count)
        #expect(Set(scenarios).count == scenarios.count)
        #expect(Set(flags).isSubset(of: Set(LaunchFlag.all)))
        #expect(scenarios.contains(UITestLaunch.defaultScenario))
    }

    @Test func aLaunchNamingNoScenarioFlagBootsTheDefault() {
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_FIXTURE"]).scenario == .partialUpload)
    }

    // Spelled from the prefix, because a literal misspelt flag is exactly what the docs lint refuses.
    private let misspeltFullBlock = LaunchFlag.prefix + "FULLBLOCK"

    @Test func aMisspeltFlagFailsTheFlagCheckAndEveryKnownFlagPassesIt() throws {
        #expect(throws: UITestLaunch.UnknownLaunchFlag(argument: misspeltFullBlock)) {
            try UITestLaunch(arguments: ["-UITEST_FIXTURE", misspeltFullBlock]).checkFlags()
        }
        try UITestLaunch(arguments: LaunchFlag.all.map(\.argument) + ["dark", "WorkoutTracker"]).checkFlags()
    }

    @MainActor
    @Test func aMisspeltScenarioFlagFailsTheBootInsteadOfBootingTheDefault() async {
        await #expect(throws: UITestLaunch.UnknownLaunchFlag.self) {
            _ = try await BootedFixture.boot([misspeltFullBlock])
        }
    }

    @Test func scenarioPriorityPicksTheEarlierArgumentWhenALaunchNamesTwo() {
        #expect(
            UITestLaunch(arguments: ["-UITEST_FULL_BLOCK", "-UITEST_LONG_SESSION"]).scenario == .longSession
        )
        #expect(
            UITestLaunch(arguments: ["-UITEST_LONG_SESSION", "-UITEST_OPEN_EXERCISES"]).scenario == .openExercises
        )
        #expect(
            UITestLaunch(
                arguments: ["-UITEST_OPEN_EXERCISES", "-UITEST_COMPLETED_OPEN_EXERCISES"]
            ).scenario == .completedOpenExercises
        )
        #expect(
            UITestLaunch(
                arguments: ["-UITEST_COMPLETED_OPEN_EXERCISES", "-UITEST_PERFECT_MOVE_ON_CELEBRATION"]
            ).scenario == .perfectMoveOnCelebration
        )
    }

    @Test func blockOverviewIsTheLaunchDestinationOnlyWhenNoScreenArgumentIsPresent() {
        #expect(UITestLaunch(arguments: ["WorkoutTracker"]).startsInBlockOverview)
        #expect(UITestLaunch(arguments: ["-UITEST_FULL_BLOCK"]).startsInBlockOverview)
        #expect(UITestLaunch(arguments: ["-UITEST_SESSION"]).startsInBlockOverview == false)
        #expect(UITestLaunch(arguments: ["-UITEST_DEVELOPER_TOOLS"]).startsInBlockOverview == false)
        #expect(UITestLaunch(arguments: ["-UITEST_SETTINGS"]).startsInBlockOverview == false)
        #expect(UITestLaunch(arguments: ["-UITEST_ONBOARDING"]).startsInBlockOverview == false)
    }

    @Test func appearanceLaunchArgumentPinsEachStoredPreference() throws {
        #expect(try UITestLaunch(arguments: ["WorkoutTracker"]).appearance == .system)
        #expect(try UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "system"]).appearance == .system)
        #expect(try UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "light"]).appearance == .light)
        #expect(try UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "dark"]).appearance == .night)
    }

    @Test func appearanceLaunchArgumentRefusesAValueThePreferenceDoesNotStore() {
        let night = #expect(throws: UITestLaunch.UnknownAppearance.self) {
            try UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "night"]).appearance
        }
        #expect(night?.description == "-UITEST_APPEARANCE takes system, light, dark, not \"night\"")
        #expect(throws: UITestLaunch.UnknownAppearance(value: "")) {
            try UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE"]).appearance
        }
    }

    @Test func dictationLaunchArgumentGivesTheCardTheTranscriptAfterIt() {
        #expect(UITestLaunch(arguments: ["WorkoutTracker"]).dictatedTranscript == nil)
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_DICTATION", "185 for 5 at 8"]).dictatedTranscript == "185 for 5 at 8")
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_DICTATION"]).dictatedTranscript == "")
    }

    @MainActor
    @Test func fullBlockLaunchSeedsFourWeeksOfTheUILaunchSessions() async throws {
        let booted = try await BootedFixture.boot(["-UITEST_FULL_BLOCK"])
        let block = try booted.block()

        #expect(exerciseNames(in: block, at: SessionAddress(week: 1, day: 1)) == ["Back Squat", "2-3:1:0 BB RDL"])
        #expect(exerciseNames(in: block, at: SessionAddress(week: 1, day: 2)) == ["Bench Press", "Pull-Up"])
        #expect(exerciseNames(in: block, at: SessionAddress(week: 1, day: 3)) == ["Deadlift"])
        #expect(exerciseNames(in: block, at: SessionAddress(week: 1, day: 4)) == ["Accessory"])
        #expect(exerciseNames(in: block, at: SessionAddress(week: 3, day: 2)) == ["Accessory"])
        #expect(block.weeks.map(\.number).sorted() == [1, 2, 3, 4])
    }

    @MainActor
    @Test func eachScenarioSeedsItsOwnBlock() async throws {
        let shapes: [(arguments: [String], weekOneDayNumbers: [Int], weekOneDayOneNames: [String])] = [
            (["-UITEST_PERFECT_MOVE_ON_CELEBRATION"], [1, 2], ["Back Squat"]),
            (["-UITEST_COMPLETED_OPEN_EXERCISES"], [1, 2, 3], ["Back Squat"]),
            (["-UITEST_OPEN_EXERCISES"], [1, 2, 3], ["Back Squat"]),
            (
                ["-UITEST_LONG_SESSION"], [1],
                [
                    "Primer Row", "Back Squat", "Bench Press", "Chest-Supported Row",
                    "Split Squat", "Hamstring Curl", "Cable Crunch", "Farmer Carry"
                ]
            ),
            (["-UITEST_FULL_BLOCK"], [1, 2, 3, 4], ["Back Squat", "2-3:1:0 BB RDL"]),
            ([], [1, 2, 3, 4], ["Back Squat", "2-3:1:0 BB RDL"])
        ]

        for shape in shapes {
            let booted = try await BootedFixture.boot(shape.arguments)
            let block = try booted.block()
            let weekOne = try #require(block.weeks.first { $0.number == 1 })

            #expect(weekOne.sessions.map(\.dayNumber).sorted() == shape.weekOneDayNumbers)
            #expect(
                exerciseNames(in: block, at: SessionAddress(week: 1, day: 1)) == shape.weekOneDayOneNames,
                "scenario \(shape.arguments)"
            )
        }
    }

    @MainActor
    @Test func bootAlwaysLeavesTheFixtureHistoryAndOnlyQueuesAWriteWhenAsked() async throws {
        let plain = try await BootedFixture.boot([])
        #expect(
            try plain.context.fetch(FetchDescriptor<LastPerformedEntry>()).map(\.resultText).sorted()
                == ["185x5@7, 195x5@8", "225x5@7", "235x5@6, 245x5@7", "245x5@6, 255x5@7"]
        )
        #expect(try plain.context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

        let pending = try await BootedFixture.boot(["-UITEST_PENDING_WRITE"])
        let queued = try pending.context.fetch(FetchDescriptor<PendingWrite>())
        #expect(queued.map(\.exercise) == [.first("2-3:1:0 BB RDL")])
        #expect(queued.map(\.setIndex) == [0])
        #expect(queued.map(\.valueToWrite) == ["225x8@8"])
    }

    @MainActor
    @Test func aPendingWriteLaunchOnAScenarioWithoutThatSetFailsTheBoot() async throws {
        // The Perfect Session's Day 1 has one Exercise, so it has no Week 1 Day 1 Exercise 2.
        await #expect(throws: ApplicationError.self) {
            _ = try await BootedFixture.boot(.perfectMoveOnCelebration, plus: ["-UITEST_PENDING_WRITE"])
        }
    }

    @MainActor
    @Test func bootLeavesNoSyncOutcomeAndNoSyncInFlight() async throws {
        for arguments in [[], ["-UITEST_FULL_BLOCK"], ["-UITEST_PENDING_WRITE"], ["-UITEST_LONG_SESSION"], ["-UITEST_ONBOARDING"]] {
            let booted = try await BootedFixture.boot(arguments)
            #expect(booted.app.sync.outcome == .clear, "\(arguments)")
            #expect(booted.app.sync.isSyncing == false, "\(arguments)")
        }
    }

    @MainActor
    @Test func onlyTheOfflineLaunchLeavesTheFixtureSheetUnreachable() async throws {
        for arguments in [[], ["-UITEST_PENDING_WRITE"]] {
            let reachable = try await BootedFixture.boot(arguments)
            #expect(
                try await reachable.sheets.listTabTitles(spreadsheetId: WorkoutFixtureScenarios.sheetId) == ["Block 27"],
                "\(arguments)"
            )
        }

        for arguments in [["-UITEST_OFFLINE"], ["-UITEST_OFFLINE", "-UITEST_PENDING_WRITE"]] {
            let offline = try await BootedFixture.boot(arguments)
            await #expect(throws: URLError.self, "\(arguments)") {
                try await offline.sheets.listTabTitles(spreadsheetId: WorkoutFixtureScenarios.sheetId)
            }
        }
    }

    @MainActor
    @Test func aSlowSyncLaunchBootsWithoutWaitingOnTheHold() async throws {
        let booted = try await BootedFixture.boot(["-UITEST_SLOW_SYNC"])
        #expect(await booted.sheets.heldTabListings == 0)

        let listing = Task { try await booted.sheets.listTabTitles(spreadsheetId: WorkoutFixtureScenarios.sheetId) }
        listing.cancel()
        await #expect(throws: CancellationError.self) { try await listing.value }
        #expect(await booted.sheets.heldTabListings == 1)
    }

    @MainActor
    @Test func onboardingBootsWithTheSyncedBlockAndNoSpreadsheetSelected() async throws {
        let booted = try await BootedFixture.boot(["-UITEST_ONBOARDING"])

        #expect(booted.app.settings.spreadsheetId == nil)
        #expect(try booted.block().tabName == "Block 27")
    }

    @MainActor
    @Test func theDefaultLaunchBenchPressEstimatesFromHistoryThenFromSetOneToday() async throws {
        let booted = try await BootedFixture.boot([])
        let history = LastPerformedLookupStore(context: booted.context).snapshot
        let dayTwo = try booted.block().session(at: SessionAddress(week: 1, day: 2))
        let sets = try #require(dayTwo?.exercises.first { $0.exerciseName == "Bench Press" }).sets.sorted { $0.index < $1.index }
        func card(_ set: ExerciseSet) -> SmartValuePillsForm {
            SmartValuePillsForm(set: set, suggestion: LoadSuggestionEngine.suggest(for: set, history: history))
        }

        #expect(card(sets[0]).weightText == "182.5")
        #expect(card(sets[0]).loadBasisLine == SmartValuePillsForm.LoadBasisLine(text: "from 195x5@8 · Block 26 W4 D1", isShown: true))

        sets[0].markLogged(SetLog(weight: .pounds(185), reps: 5, rpe: .seven), at: Date(timeIntervalSinceReferenceDate: 0))

        #expect(card(sets[1]).weightText == "185")
        #expect(card(sets[1]).loadBasisLine == SmartValuePillsForm.LoadBasisLine(text: "from Set 1 today", isShown: true))
    }

    @MainActor
    private func exerciseNames(in block: Block, at address: SessionAddress) -> [String] {
        block.session(at: address)?
            .exercises
            .sorted { $0.order < $1.order }
            .map(\.exerciseName.entered) ?? []
    }

#endif
