#if DEBUG
    struct LaunchFlag: Hashable, Sendable {
        let argument: String
        let meaning: String
        var actsWithoutFixture = false

        /// What every launch flag starts with, so `UITestLaunch.checkFlags` can tell a misspelt
        /// flag from an argument that is not one.
        static let prefix = "-UITEST_"

        static let fixture = LaunchFlag(
            argument: "-UITEST_FIXTURE",
            meaning:
                "Runs on an in-memory store, synced from the Scenario's local workbook at boot, with a faked sign-in and"
                + " a Sheets client that never reaches Google. The fixture Sheet then reads as Offline, so a log stays queued.",
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
            meaning: "Seeds the perfect-move-on-celebration workbook, whose Week 1 Day 1 has every Set Logged or Skipped,"
                + " and requests the Move On Celebration."
        )

        static let completedOpenExercises = LaunchFlag(
            argument: "-UITEST_COMPLETED_OPEN_EXERCISES",
            meaning: "Seeds the completed-open-exercises workbook: one Week whose Day 2 has every Set Logged while Day 1's"
                + " Back Squat still has a Pending Set."
        )

        static let openExercises = LaunchFlag(
            argument: "-UITEST_OPEN_EXERCISES",
            meaning: "Seeds the open-exercises workbook: one Week whose Days 1 to 3 each hold one Open Exercise with some Sets Logged."
        )

        static let longSession = LaunchFlag(
            argument: "-UITEST_LONG_SESSION",
            meaning: "Seeds the long-session workbook: one Session of eight Exercises with only the first logged."
        )

        static let fullBlock = LaunchFlag(
            argument: "-UITEST_FULL_BLOCK",
            meaning: "Seeds the full-block workbook: four Weeks of four Sessions, every one an Available Session."
        )

        static let partialUpload = LaunchFlag(
            argument: "-UITEST_PARTIAL_UPLOAD",
            meaning:
                "Seeds the partial-upload workbook: four Weeks of four Days, eleven of them Unavailable Sessions."
                + " A launch that names no Scenario flag gets it too."
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
            meaning:
                "Logs 225x8@8 on Week 1 Day 1's BB RDL at boot without flushing it, and keeps the fixture Sheet reachable,"
                + " so a sync writes it to the Scenario's own workbook and reloads the Block from it."
        )

        static let slowSync = LaunchFlag(
            argument: "-UITEST_SLOW_SYNC",
            meaning: "Makes every tab list after the boot wait 20 seconds, so a sync stays in flight."
        )

        static let lateSignIn = LaunchFlag(
            argument: "-UITEST_LATE_SIGN_IN",
            meaning: "Starts signed out and signs in 3 seconds after launch, as restoring a Google sign-in does on a device."
        )

        static let currentSessionOverride = LaunchFlag(
            argument: "-UITEST_CURRENT_SESSION_OVERRIDE",
            meaning:
                "Makes Week 1 Day 3 the Current Session when the Scenario gives it Exercises, as Full Block does;"
                + " otherwise the Current Session stays."
        )

        static let moveOnCelebration = LaunchFlag(
            argument: "-UITEST_MOVE_ON_CELEBRATION",
            meaning: "Requests the Move On Celebration, which shows only when the Current Session offers Move On."
        )

        static let appearance = LaunchFlag(
            argument: "-UITEST_APPEARANCE",
            meaning: "Takes one of \(AppearancePreference.allCases.map(\.rawValue).joined(separator: ", ")) as the next argument"
                + " and pins the appearance to it; any other value stops the app."
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
            .partialUpload,
            .disableAnimations,
            .disableLiveActivities,
            .pendingWrite,
            .slowSync,
            .lateSignIn,
            .currentSessionOverride,
            .moveOnCelebration,
            .appearance,
            .longCelebrationQuote
        ]
    }
#endif
