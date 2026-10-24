#if DEBUG
    import Foundation

    /// The launch configuration of a UI-test run, read once from the process arguments.
    ///
    /// Every flag the app honours is read here, so a test can construct a launch from a literal
    /// argument list instead of launching the app to find out what a flag does.
    struct UITestLaunch: Sendable {
        /// The workbook each Scenario flag boots the fixture into, in priority order: the first flag
        /// present in a launch wins. Each flag is the prefix and its workbook's name in upper snake
        /// case, so the UI launch and the CLI's `--scenario` share one vocabulary.
        static let scenarioFlags: [(flag: LaunchFlag, scenario: WorkbookScenario)] = LaunchFlag.all.compactMap { flag in
            guard case .scenario(let scenario) = flag.kind else { return nil }
            return (flag, scenario)
        }

        /// The workbook a launch that names no Scenario flag boots into.
        static let defaultScenario = WorkbookScenario.partialUpload

        /// The flags that send the app somewhere other than the Block overview.
        static let screenFlags = LaunchFlag.all.filter { $0.kind == .screen }

        private let arguments: [String]

        init(arguments: [String]) {
            self.arguments = arguments
        }

        var runsOnFixture: Bool { has(.fixture) }

        var disablesAnimations: Bool { has(.disableAnimations) }

        /// A Live Activity outlives the test's app process. The next test session's reinstall ends
        /// it, liveactivitiesd launches the app in the background while Xcode's own launch is
        /// pending, and SpringBoard kills that instance and hands Xcode no process (#537).
        var disablesLiveActivities: Bool { has(.disableLiveActivities) }

        /// A test that needs Live Activities leaves one up when its process ends. Reinstalled for
        /// the next session, the app is relaunched for it by liveactivitiesd with no arguments, and
        /// XCUITest can attach to that instance, which lands on onboarding. A launch that ends them
        /// all leaves nothing to relaunch for.
        var endsLiveActivities: Bool { has(.endLiveActivities) }

        var startsWithPendingWrite: Bool { has(.pendingWrite) }

        var startsOffline: Bool { has(.offline) }

        var slowsSync: Bool { has(.slowSync) }

        var signsInLate: Bool { has(.lateSignIn) }

        var startsInDeveloperTools: Bool { has(.developerTools) }

        var startsInSettings: Bool { has(.settings) }

        /// Boots signed-in but with **no** spreadsheet selected, so the app shows onboarding's sheet
        /// picker. Combined with the seeded (stale) Block this exercises the onboarding selection
        /// path that previously bypassed the safe Settings switch flow.
        var startsInOnboarding: Bool { has(.onboarding) }

        var startsWithCurrentSessionOverride: Bool { has(.currentSessionOverride) }

        var startsWithMoveOnCelebration: Bool { has(.moveOnCelebration) }

        var startsWithPerfectMoveOnCelebration: Bool { has(.perfectMoveOnCelebration) }

        var showsLongCelebrationQuote: Bool { has(.longCelebrationQuote) }

        var startsInBlockOverview: Bool {
            !Self.screenFlags.contains(where: has)
        }

        var scenario: WorkbookScenario {
            Self.scenarioFlags.first { has($0.flag) }?.scenario ?? Self.defaultScenario
        }

        /// Throws for the first argument spelled like a launch flag that `LaunchFlag.all` does not
        /// hold, so a misspelt Scenario flag stops the boot instead of quietly booting the default.
        /// It throws too for a Value flag with no value after it, and for a flag whose `needs` the
        /// launch leaves out.
        func checkFlags() throws(UnreadableLaunch) {
            for (index, argument) in arguments.enumerated() where argument.hasPrefix(LaunchFlag.prefix) {
                guard let flag = LaunchFlag.all.first(where: { $0.argument == argument }) else {
                    throw .unknownFlag(argument)
                }
                if flag.kind == .value, arguments.dropFirst(index + 1).first?.hasPrefix(LaunchFlag.prefix) ?? true {
                    throw .missingValue(flag)
                }
                if let need = flag.needs.first(where: { !has($0) }) {
                    throw .missingNeed(flag, need)
                }
            }
        }

        enum UnreadableLaunch: Error, Equatable, CustomStringConvertible {
            case unknownFlag(String)
            case missingValue(LaunchFlag)
            case missingNeed(LaunchFlag, LaunchFlag)

            var description: String {
                switch self {
                case .unknownFlag(let argument):
                    "\(argument) is not a launch flag. .agents/skills/verify/launch-flags.md lists every one."
                case .missingValue(let flag):
                    "\(flag.argument) takes a value as the next argument. .agents/skills/verify/launch-flags.md says what it takes."
                case .missingNeed(let flag, let need):
                    "\(flag.argument) acts only with \(need.argument). .agents/skills/verify/launch-flags.md lists every flag."
                }
            }
        }

        var appearance: AppearancePreference {
            get throws(UnknownAppearance) {
                guard let value = value(of: .appearance) else { return .system }
                guard let preference = AppearancePreference(rawValue: value) else {
                    throw UnknownAppearance(value: value)
                }
                return preference
            }
        }

        /// What the fixture's mic hears on every press; nil leaves the card without a mic.
        var dictatedTranscript: String? {
            value(of: .dictation)
        }

        /// The WAV file the fixture's mic records on every press; nil records nothing.
        var recordingPath: String? {
            value(of: .recording)
        }

        /// The host folder the real recording engine reads its model from; nil keeps the stand-in.
        var speechModelsPath: String? {
            value(of: .speechModels)
        }

        /// How long a press waits for the Recording Transcript; nil keeps the shipped Decision
        /// Deadline.
        var decisionDeadline: Duration? {
            get throws(UnreadableDecisionDeadline) {
                guard let value = value(of: .decisionDeadline) else { return nil }
                guard let seconds = Double(value), seconds > 0 else { throw UnreadableDecisionDeadline(value: value) }
                return .milliseconds(Int((seconds * 1000).rounded()))
            }
        }

        /// The argument after `flag`, empty when it comes last; nil when the launch lacks `flag`.
        private func value(of flag: LaunchFlag) -> String? {
            guard let flagIndex = arguments.firstIndex(of: flag.argument) else { return nil }
            return arguments.dropFirst(flagIndex + 1).first ?? ""
        }

        struct UnreadableDecisionDeadline: Error, Equatable, CustomStringConvertible {
            let value: String

            var description: String {
                "\(LaunchFlag.decisionDeadline.argument) takes a number of seconds above 0, not \"\(value)\""
            }
        }

        struct UnknownAppearance: Error, Equatable, CustomStringConvertible {
            let value: String

            var description: String {
                let accepted = AppearancePreference.allCases.map(\.rawValue).joined(separator: ", ")
                return "\(LaunchFlag.appearance.argument) takes \(accepted), not \"\(value)\""
            }
        }

        private func has(_ flag: LaunchFlag) -> Bool {
            arguments.contains(flag.argument)
        }
    }
#endif
