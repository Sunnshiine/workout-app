#if DEBUG
    import Foundation

    /// The launch configuration of a UI-test run, read once from the process arguments.
    ///
    /// Every flag the app honours lives here, so a test can construct a launch from a literal
    /// argument list instead of launching the app to find out what a flag does.
    struct UITestLaunch: Sendable {
        /// Which fixture Block `UITestFixture.seed` inserts.
        enum Scenario: Sendable {
            case perfectMoveOnCelebration
            case completedOpenExercises
            case openExercises
            case longSession
            case fullBlock
            case partialUpload
        }

        /// The scenario priority: the first argument present in a launch wins, and a launch that
        /// names none gets `.partialUpload`.
        private static let scenarioArguments: [(argument: String, scenario: Scenario)] = [
            ("-UITEST_PERFECT_MOVE_ON_CELEBRATION", .perfectMoveOnCelebration),
            ("-UITEST_COMPLETED_OPEN_EXERCISES", .completedOpenExercises),
            ("-UITEST_OPEN_EXERCISES", .openExercises),
            ("-UITEST_LONG_SESSION", .longSession),
            ("-UITEST_FULL_BLOCK", .fullBlock)
        ]

        /// The arguments that send the app somewhere other than the Block overview.
        private static let screenArguments = [
            "-UITEST_SESSION",
            "-UITEST_DEVELOPER_TOOLS",
            "-UITEST_SETTINGS",
            "-UITEST_ONBOARDING"
        ]

        private let arguments: [String]

        init(arguments: [String]) {
            self.arguments = arguments
        }

        var disablesAnimations: Bool { has("-UITEST_DISABLE_ANIMATIONS") }

        var startsWithPendingWrite: Bool { has("-UITEST_PENDING_WRITE") }

        var startsInDeveloperTools: Bool { has("-UITEST_DEVELOPER_TOOLS") }

        var startsInSettings: Bool { has("-UITEST_SETTINGS") }

        /// Boots signed-in but with **no** spreadsheet selected, so the app shows onboarding's sheet
        /// picker. Combined with the seeded (stale) Block this exercises the onboarding selection
        /// path that previously bypassed the safe Settings switch flow.
        var startsInOnboarding: Bool { has("-UITEST_ONBOARDING") }

        var startsWithCurrentSessionOverride: Bool { has("-UITEST_CURRENT_SESSION_OVERRIDE") }

        var startsWithMoveOnCelebration: Bool { has("-UITEST_MOVE_ON_CELEBRATION") }

        var startsWithPerfectMoveOnCelebration: Bool { has("-UITEST_PERFECT_MOVE_ON_CELEBRATION") }

        var startsInBlockOverview: Bool {
            !Self.screenArguments.contains(where: arguments.contains)
        }

        var scenario: Scenario {
            Self.scenarioArguments.first { has($0.argument) }?.scenario ?? .partialUpload
        }

        var appearanceOverride: AppearancePreference? {
            guard
                let flagIndex = arguments.firstIndex(of: "-UITEST_APPEARANCE"),
                arguments.indices.contains(arguments.index(after: flagIndex))
            else {
                return nil
            }
            return AppearancePreference(rawValue: arguments[arguments.index(after: flagIndex)])
        }

        private func has(_ argument: String) -> Bool {
            arguments.contains(argument)
        }
    }
#endif
