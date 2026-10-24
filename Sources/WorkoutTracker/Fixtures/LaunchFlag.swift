#if DEBUG
    struct LaunchFlag: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case `switch`
            case screen
            case scenario(WorkbookScenario)
            case value
        }

        let argument: String
        var kind = Kind.switch
        let meaning: String
        var actsWithoutFixture = false
        var needs: [LaunchFlag] = []

        /// What every launch flag starts with, so `UITestLaunch.checkFlags` can tell a misspelt
        /// flag from an argument that is not one.
        static let prefix = "-UITEST_"

        static let fixture = LaunchFlag(
            argument: "-UITEST_FIXTURE",
            meaning:
                "Runs on an in-memory store, synced from the Scenario's local workbook at boot, with a faked sign-in and"
                + " a Sheets client that never reaches Google. A log then flushes into that workbook, as it would into the"
                + " coach's Sheet.",
            actsWithoutFixture: true
        )

        static let session = LaunchFlag(
            argument: "-UITEST_SESSION",
            kind: .screen,
            meaning: "Leaves Block Overview closed, so the app opens on the Current Session."
        )

        static let developerTools = LaunchFlag(
            argument: "-UITEST_DEVELOPER_TOOLS",
            kind: .screen,
            meaning: "Opens Developer Tools in place of the Session screen."
        )

        static let settings = LaunchFlag(
            argument: "-UITEST_SETTINGS",
            kind: .screen,
            meaning: "Opens Settings in place of the Session screen."
        )

        static let onboarding = LaunchFlag(
            argument: "-UITEST_ONBOARDING",
            kind: .screen,
            meaning: "Leaves the spreadsheet unselected, so the app opens on onboarding's sheet picker."
        )

        static let perfectMoveOnCelebration = LaunchFlag(
            argument: "-UITEST_PERFECT_MOVE_ON_CELEBRATION",
            kind: .scenario(.perfectMoveOnCelebration),
            meaning: "Seeds the perfect-move-on-celebration workbook, whose Week 1 Day 1 has every Set Logged or Skipped,"
                + " and requests the Move On Celebration."
        )

        static let completedOpenExercises = LaunchFlag(
            argument: "-UITEST_COMPLETED_OPEN_EXERCISES",
            kind: .scenario(.completedOpenExercises),
            meaning: "Seeds the completed-open-exercises workbook: one Week whose Day 2 has every Set Logged while Day 1's"
                + " Back Squat still has a Pending Set."
        )

        static let openExercises = LaunchFlag(
            argument: "-UITEST_OPEN_EXERCISES",
            kind: .scenario(.openExercises),
            meaning: "Seeds the open-exercises workbook: one Week whose Days 1 to 3 each hold one Open Exercise with some Sets Logged."
        )

        static let longSession = LaunchFlag(
            argument: "-UITEST_LONG_SESSION",
            kind: .scenario(.longSession),
            meaning: "Seeds the long-session workbook: one Session of eight Exercises with only the first logged."
        )

        static let fullBlock = LaunchFlag(
            argument: "-UITEST_FULL_BLOCK",
            kind: .scenario(.fullBlock),
            meaning: "Seeds the full-block workbook: four Weeks of four Sessions, every one an Available Session."
        )

        static let partialUpload = LaunchFlag(
            argument: "-UITEST_PARTIAL_UPLOAD",
            kind: .scenario(.partialUpload),
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

        static let endLiveActivities = LaunchFlag(
            argument: "-UITEST_END_LIVE_ACTIVITIES",
            meaning: "Ends every Live Activity still up from an earlier process at launch, so one never outlives a test session.",
            actsWithoutFixture: true
        )

        static let pendingWrite = LaunchFlag(
            argument: "-UITEST_PENDING_WRITE",
            meaning:
                "Logs 225x8@8 on Week 1 Day 1's BB RDL at boot without flushing it, so a sync writes it to the Scenario's"
                + " own workbook and reloads the Block from it."
        )

        static let offline = LaunchFlag(
            argument: "-UITEST_OFFLINE",
            meaning: "Makes the fixture Sheet read as Offline after the boot, so a log stays queued and the header reads"
                + " `N unsynced`."
        )

        static let slowSync = LaunchFlag(
            argument: "-UITEST_SLOW_SYNC",
            meaning: "Makes every tab list after the boot wait 20 seconds, so a sync stays in flight."
        )

        static let lateSignIn = LaunchFlag(
            argument: "-UITEST_LATE_SIGN_IN",
            meaning:
                "Restores the sign-in for 3 seconds after launch, showing onboarding meanwhile, then signs in,"
                + " as restoring a Google sign-in does on a device."
        )

        static let currentSessionOverride = LaunchFlag(
            argument: "-UITEST_CURRENT_SESSION_OVERRIDE",
            meaning:
                "Makes Week 1 Day 3 the Current Session when the Scenario gives it Exercises, as Full Block does;"
                + " otherwise the Current Session stays."
        )

        static let moveOnCelebration = LaunchFlag(
            argument: "-UITEST_MOVE_ON_CELEBRATION",
            meaning: "Requests the Move On Celebration for the Current Session."
        )

        static let appearance = LaunchFlag(
            argument: "-UITEST_APPEARANCE",
            kind: .value,
            meaning: "Takes one of \(AppearancePreference.allCases.map(\.rawValue).joined(separator: ", ")) as the next argument"
                + " and pins the appearance to it; any other value stops the app."
        )

        static let longCelebrationQuote = LaunchFlag(
            argument: "-UITEST_LONG_CELEBRATION_QUOTE",
            meaning: "Shows a long fixture quote in the Move On Celebration in place of a random approved one.",
            actsWithoutFixture: true
        )

        static let dictation = LaunchFlag(
            argument: "-UITEST_DICTATION",
            kind: .value,
            meaning: "Takes a transcript as the next argument and gives the Active Set Card a mic that hears it,"
                + " in place of SpeechAnalyzer, which does not run in the Simulator."
        )

        static let recording = LaunchFlag(
            argument: "-UITEST_RECORDING",
            kind: .value,
            meaning: "Takes the path of a 16 kHz mono WAV file as the next argument, which the fixture's mic records on"
                + " every press for the recording engine to read.",
            needs: [.dictation]
        )

        static let speechModels = LaunchFlag(
            argument: "-UITEST_SPEECH_MODELS",
            kind: .value,
            meaning: "Takes a host folder holding Whisper small and its tokenizer in the Hugging Face download layout,"
                + " and reads each press's recording with the real recording engine from it in place of the stand-in."
                + " Stops the launch if the folder lacks the model.",
            needs: [.dictation]
        )

        static let decisionDeadline = LaunchFlag(
            argument: "-UITEST_DECISION_DEADLINE",
            kind: .value,
            meaning: "Takes seconds as the next argument and waits that long for the Recording Transcript in place of"
                + " the shipped Decision Deadline, since a Simulator decode takes seconds. Any value but seconds above 0"
                + " stops the app."
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
            .endLiveActivities,
            .pendingWrite,
            .offline,
            .slowSync,
            .lateSignIn,
            .currentSessionOverride,
            .moveOnCelebration,
            .appearance,
            .longCelebrationQuote,
            .dictation,
            .recording,
            .speechModels,
            .decisionDeadline
        ]
    }
#endif
