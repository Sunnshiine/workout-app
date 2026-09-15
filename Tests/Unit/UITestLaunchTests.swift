import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

#if DEBUG

    @Test func launchFlagsAreOffWithoutTheirArgument() {
        let launch = UITestLaunch(arguments: ["WorkoutTracker"])

        #expect(launch.disablesAnimations == false)
        #expect(launch.disablesLiveActivities == false)
        #expect(launch.startsWithPendingWrite == false)
        #expect(launch.startsInDeveloperTools == false)
        #expect(launch.startsInSettings == false)
        #expect(launch.startsInOnboarding == false)
        #expect(launch.startsWithCurrentSessionOverride == false)
        #expect(launch.startsWithMoveOnCelebration == false)
        #expect(launch.startsWithPerfectMoveOnCelebration == false)
        #expect(launch.appearanceOverride == nil)
    }

    @Test func eachLaunchFlagParsesFromItsArgument() {
        #expect(UITestLaunch(arguments: ["-UITEST_DISABLE_ANIMATIONS"]).disablesAnimations)
        #expect(UITestLaunch(arguments: ["-UITEST_DISABLE_LIVE_ACTIVITIES"]).disablesLiveActivities)
        #expect(UITestLaunch(arguments: ["-UITEST_PENDING_WRITE"]).startsWithPendingWrite)
        #expect(UITestLaunch(arguments: ["-UITEST_DEVELOPER_TOOLS"]).startsInDeveloperTools)
        #expect(UITestLaunch(arguments: ["-UITEST_SETTINGS"]).startsInSettings)
        #expect(UITestLaunch(arguments: ["-UITEST_ONBOARDING"]).startsInOnboarding)
        #expect(UITestLaunch(arguments: ["-UITEST_CURRENT_SESSION_OVERRIDE"]).startsWithCurrentSessionOverride)
        #expect(UITestLaunch(arguments: ["-UITEST_MOVE_ON_CELEBRATION"]).startsWithMoveOnCelebration)
        #expect(UITestLaunch(arguments: ["-UITEST_PERFECT_MOVE_ON_CELEBRATION"]).startsWithPerfectMoveOnCelebration)
    }

    @Test func scenarioFallsBackToPartialUploadAndEachArgumentSelectsItsScenario() {
        #expect(UITestLaunch(arguments: ["WorkoutTracker"]).scenario == .partialUpload)
        #expect(UITestLaunch(arguments: ["-UITEST_PARTIAL_BLOCK"]).scenario == .partialUpload)
        #expect(UITestLaunch(arguments: ["-UITEST_FULL_BLOCK"]).scenario == .fullBlock)
        #expect(UITestLaunch(arguments: ["-UITEST_LONG_SESSION"]).scenario == .longSession)
        #expect(UITestLaunch(arguments: ["-UITEST_OPEN_EXERCISES"]).scenario == .openExercises)
        #expect(UITestLaunch(arguments: ["-UITEST_COMPLETED_OPEN_EXERCISES"]).scenario == .completedOpenExercises)
        #expect(
            UITestLaunch(arguments: ["-UITEST_PERFECT_MOVE_ON_CELEBRATION"]).scenario == .perfectMoveOnCelebration
        )
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

    @Test func appearanceLaunchArgumentParsesSupportedAppearances() {
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "light"]).appearanceOverride == .light)
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "dark"]).appearanceOverride == .dark)
        #expect(
            UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "system"]).appearanceOverride == .system
        )
    }

    @Test func appearanceLaunchArgumentIgnoresMissingOrUnsupportedAppearances() {
        #expect(UITestLaunch(arguments: ["WorkoutTracker"]).appearanceOverride == nil)
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE"]).appearanceOverride == nil)
        #expect(UITestLaunch(arguments: ["WorkoutTracker", "-UITEST_APPEARANCE", "black"]).appearanceOverride == nil)
    }

    @MainActor
    @Test func fullBlockLaunchSeedsFourWeeksOfTheUILaunchSessions() throws {
        let seeded = try seed(arguments: ["-UITEST_FULL_BLOCK"])
        defer { withExtendedLifetime(seeded.container) {} }

        #expect(exerciseNames(in: seeded.block, week: 1, day: 1) == ["Back Squat", "2-3:1:0 BB RDL"])
        #expect(exerciseNames(in: seeded.block, week: 1, day: 2) == ["Bench Press", "Pull-Up"])
        #expect(exerciseNames(in: seeded.block, week: 1, day: 3) == ["Deadlift"])
        #expect(exerciseNames(in: seeded.block, week: 1, day: 4) == ["Accessory W1 D4"])
        #expect(exerciseNames(in: seeded.block, week: 3, day: 2) == ["Accessory W3 D2"])
        #expect(seeded.block.weeks.map(\.number).sorted() == [1, 2, 3, 4])
    }

    @MainActor
    @Test func eachScenarioSeedsItsOwnBlock() throws {
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
            let seeded = try seed(arguments: shape.arguments)
            defer { withExtendedLifetime(seeded.container) {} }
            let weekOne = try #require(seeded.block.weeks.first { $0.number == 1 })

            #expect(weekOne.sessions.map(\.dayNumber).sorted() == shape.weekOneDayNumbers)
            #expect(
                exerciseNames(in: seeded.block, week: 1, day: 1) == shape.weekOneDayOneNames,
                "scenario \(shape.arguments)"
            )
        }
    }

    @MainActor
    @Test func seedingAlwaysInsertsBackSquatHistoryAndOnlyQueuesAWriteWhenAsked() throws {
        let plain = try seed(arguments: [])
        defer { withExtendedLifetime(plain.container) {} }
        #expect(
            try plain.context.fetch(FetchDescriptor<LastPerformedEntry>()).map(\.resultText).sorted()
                == ["225x5@7", "235x5@6, 245x5@7", "245x5@6, 255x5@7"]
        )
        #expect(try plain.context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

        let pending = try seed(arguments: ["-UITEST_PENDING_WRITE"])
        defer { withExtendedLifetime(pending.container) {} }
        #expect(try pending.context.fetch(FetchDescriptor<PendingWrite>()).map(\.valueToWrite) == ["185x5@8"])
    }

    @MainActor
    private func seed(arguments: [String]) throws -> (container: ModelContainer, context: ModelContext, block: Block) {
        let container = try ModelContainer(
            for: Block.self,
            PendingWrite.self,
            WriteTargetAuditEntry.self,
            LastPerformedEntry.self,
            configurations: ModelConfiguration("launch-\(UUID().uuidString)", isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        try UITestFixture.seed(into: context, launch: UITestLaunch(arguments: arguments))
        let blocks = try context.fetch(FetchDescriptor<Block>())
        return (container, context, try #require(blocks.first))
    }

    @MainActor
    private func exerciseNames(in block: Block, week: Int, day: Int) -> [String] {
        block.weeks
            .first { $0.number == week }?
            .sessions
            .first { $0.dayNumber == day }?
            .exercises
            .sorted { $0.order < $1.order }
            .map(\.name) ?? []
    }

#endif
