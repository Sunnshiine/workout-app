#if DEBUG
    /// Every launch argument the app honours. `scripts/lint-doc-symbols.py` fails a `-UITEST_`
    /// literal anywhere else in the app's sources, so a flag cannot be read without a case here.
    enum LaunchFlag: String, CaseIterable, Sendable {
        case fixture = "-UITEST_FIXTURE"
        case session = "-UITEST_SESSION"
        case developerTools = "-UITEST_DEVELOPER_TOOLS"
        case settings = "-UITEST_SETTINGS"
        case onboarding = "-UITEST_ONBOARDING"
        case perfectMoveOnCelebration = "-UITEST_PERFECT_MOVE_ON_CELEBRATION"
        case completedOpenExercises = "-UITEST_COMPLETED_OPEN_EXERCISES"
        case openExercises = "-UITEST_OPEN_EXERCISES"
        case longSession = "-UITEST_LONG_SESSION"
        case fullBlock = "-UITEST_FULL_BLOCK"
        case disableAnimations = "-UITEST_DISABLE_ANIMATIONS"
        case disableLiveActivities = "-UITEST_DISABLE_LIVE_ACTIVITIES"
        case pendingWrite = "-UITEST_PENDING_WRITE"
        case slowSync = "-UITEST_SLOW_SYNC"
        case currentSessionOverride = "-UITEST_CURRENT_SESSION_OVERRIDE"
        case moveOnCelebration = "-UITEST_MOVE_ON_CELEBRATION"
        case appearance = "-UITEST_APPEARANCE"
        case longCelebrationQuote = "-UITEST_LONG_CELEBRATION_QUOTE"

        /// The row `.agents/skills/verify/launch-flags.md` prints for the flag.
        var meaning: String {
            switch self {
            case .fixture:
                "Runs on an in-memory store with a fixture Block, a faked sign-in, and a Sheets client that never reaches Google."
            case .session:
                "Leaves Block Overview closed, so the app opens on the Current Session."
            case .developerTools:
                "Opens Developer Tools in place of the Session screen."
            case .settings:
                "Opens Settings in place of the Session screen."
            case .onboarding:
                "Leaves the spreadsheet unselected, so the app opens on onboarding's sheet picker."
            case .perfectMoveOnCelebration:
                "Seeds a Block whose Week 1 Day 1 has every Set Logged or Skipped, and requests the Move On Celebration."
            case .completedOpenExercises:
                "Seeds one Week whose Day 2 has every Set Logged while Day 1's Back Squat still has a Pending Set."
            case .openExercises:
                "Seeds one Week whose Days 1 to 3 each hold one Open Exercise with some Sets Logged."
            case .longSession:
                "Seeds one Session of eight Exercises with only the first logged."
            case .fullBlock:
                "Seeds four Weeks of four Sessions, every one an Available Session."
            case .disableAnimations:
                "Turns off UIKit animations and drops the animation from every SwiftUI transaction."
            case .disableLiveActivities:
                "Reports Live Activities as disabled, so no Live Activity starts."
            case .pendingWrite:
                "Seeds one queued Set Log write for Week 1 Day 1's Back Squat."
            case .slowSync:
                "Makes the fixture Sheets client wait 20 seconds before it lists tabs, so a sync stays in flight."
            case .currentSessionOverride:
                "Makes Week 1 Day 3 the Current Session."
            case .moveOnCelebration:
                "Requests the Move On Celebration, which shows only when the Current Session offers Move On."
            case .appearance:
                "Takes light, dark, or system as the next argument and pins the appearance to it; any other value stops the app."
            case .longCelebrationQuote:
                "Shows a long fixture quote in the Move On Celebration in place of a random approved one."
            }
        }
    }
#endif
