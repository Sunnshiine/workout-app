#if DEBUG
    /// Every launch argument the app honours, with the row `.agents/skills/verify/launch-flags.md`
    /// prints for it. `scripts/lint-doc-symbols.py` fails a `-UITEST_` literal anywhere else in the
    /// app's sources, and a flag spelled here but left out of `all`, so a flag cannot be read
    /// without a meaning or go missing from the table.
    struct LaunchFlag: Hashable, Sendable {
        let argument: String
        let meaning: String
        /// False for a flag the app reads only on the fixture launch path, so it does nothing without `fixture`.
        var actsWithoutFixture = false

        static let fixture = LaunchFlag(
            argument: "-UITEST_FIXTURE",
            meaning: "Runs on an in-memory store with a fixture Block, a faked sign-in, and a Sheets client that never reaches Google.",
            actsWithoutFixture: true
        )

        static let session = LaunchFlag(
            argument: "-UITEST_SESSION",
            meaning: "Leaves Block Overview closed, so the app opens on the Current Session."
        )

        static let developerTools = LaunchFlag(
            argument: "-UITEST_DEVELOPER_TOOLS",
            meaning: "Opens Developer Tools in place of the Session screen."
        )

        static let settings = LaunchFlag(
            argument: "-UITEST_SETTINGS",
            meaning: "Opens Settings in place of the Session screen."
        )

        static let onboarding = LaunchFlag(
            argument: "-UITEST_ONBOARDING",
            meaning: "Leaves the spreadsheet unselected, so the app opens on onboarding's sheet picker."
        )

        static let perfectMoveOnCelebration = LaunchFlag(
            argument: "-UITEST_PERFECT_MOVE_ON_CELEBRATION",
            meaning: "Seeds a Block whose Week 1 Day 1 has every Set Logged or Skipped, and requests the Move On Celebration."
        )

        static let completedOpenExercises = LaunchFlag(
            argument: "-UITEST_COMPLETED_OPEN_EXERCISES",
            meaning: "Seeds one Week whose Day 2 has every Set Logged while Day 1's Back Squat still has a Pending Set."
        )

        static let openExercises = LaunchFlag(
            argument: "-UITEST_OPEN_EXERCISES",
            meaning: "Seeds one Week whose Days 1 to 3 each hold one Open Exercise with some Sets Logged."
        )

        static let longSession = LaunchFlag(
            argument: "-UITEST_LONG_SESSION",
            meaning: "Seeds one Session of eight Exercises with only the first logged."
        )

        static let fullBlock = LaunchFlag(
            argument: "-UITEST_FULL_BLOCK",
            meaning: "Seeds four Weeks of four Sessions, every one an Available Session."
        )

        static let disableAnimations = LaunchFlag(
            argument: "-UITEST_DISABLE_ANIMATIONS",
            meaning: "Turns off UIKit animations and drops the animation from every SwiftUI transaction."
        )

        static let disableLiveActivities = LaunchFlag(
            argument: "-UITEST_DISABLE_LIVE_ACTIVITIES",
            meaning: "Reports Live Activities as disabled, so no Live Activity starts.",
            actsWithoutFixture: true
        )

        static let pendingWrite = LaunchFlag(
            argument: "-UITEST_PENDING_WRITE",
            meaning: "Seeds one queued Set Log write for Week 1 Day 1's Back Squat."
        )

        static let slowSync = LaunchFlag(
            argument: "-UITEST_SLOW_SYNC",
            meaning: "Makes the fixture Sheets client wait 20 seconds before it lists tabs, so a sync stays in flight."
        )

        static let currentSessionOverride = LaunchFlag(
            argument: "-UITEST_CURRENT_SESSION_OVERRIDE",
            meaning:
                "Makes Week 1 Day 3 the Current Session when the Scenario gives it Exercises, as Full Block does; otherwise the Current Session stays."
        )

        static let moveOnCelebration = LaunchFlag(
            argument: "-UITEST_MOVE_ON_CELEBRATION",
            meaning: "Requests the Move On Celebration, which shows only when the Current Session offers Move On."
        )

        static let appearance = LaunchFlag(
            argument: "-UITEST_APPEARANCE",
            meaning:
                "Takes one of \(AppearancePreference.allCases.map(\.rawValue).joined(separator: ", ")) as the next argument and pins the appearance to it; any other value stops the app."
        )

        static let longCelebrationQuote = LaunchFlag(
            argument: "-UITEST_LONG_CELEBRATION_QUOTE",
            meaning: "Shows a long fixture quote in the Move On Celebration in place of a random approved one.",
            actsWithoutFixture: true
        )

        static let all: [LaunchFlag] = [
            .fixture,
            .session,
            .developerTools,
            .settings,
            .onboarding,
            .perfectMoveOnCelebration,
            .completedOpenExercises,
            .openExercises,
            .longSession,
            .fullBlock,
            .disableAnimations,
            .disableLiveActivities,
            .pendingWrite,
            .slowSync,
            .currentSessionOverride,
            .moveOnCelebration,
            .appearance,
            .longCelebrationQuote
        ]
    }
#endif
