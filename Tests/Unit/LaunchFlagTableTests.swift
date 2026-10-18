import Foundation
import Testing

@testable import WorkoutTracker

#if DEBUG

    private let launchFlagTablePath = ".agents/skills/verify/launch-flags.md"

    /// A list as a sentence reads it, with no locale deciding the join, since the table is checked in.
    private func listed(_ items: [String]) -> String {
        guard items.count > 2, let last = items.last else { return items.joined(separator: " and ") }
        return items.dropLast().joined(separator: ", ") + ", and " + last
    }

    private func launchFlagTable(
        _ flags: [LaunchFlag],
        scenarios: [LaunchFlag],
        screens: [LaunchFlag]
    ) -> String {
        let alone = flags.filter { $0.actsWithoutFixture && $0 != .fixture }.map { "`\($0.argument)`" }
        let fixtureRule =
            alone.isEmpty
            ? "Every flag acts only when the launch also passes `\(LaunchFlag.fixture.argument)`."
            : "Every flag but \(listed(alone)) acts only when the launch also passes `\(LaunchFlag.fixture.argument)`."
        let header = """
            <!-- Generated from LaunchFlag in Sources/WorkoutTracker/Fixtures/LaunchFlag.swift. Do not edit.
                 Regenerate: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests -->
            # Launch flags

            With no Scenario flag, the fixture seeds a Partially Uploaded Block. When a launch passes more
            than one Scenario flag, the lowest Scenario number wins. \(fixtureRule)

            | Flag | Kind | Meaning |
            | --- | --- | --- |

            """
        return header
            + flags.map { flag in
                let kind =
                    scenarios.firstIndex(of: flag).map { "Scenario \($0 + 1)" }
                    ?? (screens.contains(flag) ? "Screen" : "Switch")
                return "| `\(flag.argument)` | \(kind) | \(flag.meaning) |\n"
            }.joined()
    }

    @Test func launchFlagTableMatchesTheRegistry() throws {
        let table = launchFlagTable(
            LaunchFlag.all,
            scenarios: UITestLaunch.scenarioFlags.map(\.flag),
            screens: UITestLaunch.screenFlags
        )
        if ProcessInfo.processInfo.environment["RECORD_LAUNCH_FLAGS"] == "1" {
            let url = try RepositoryFiles.existingURL(of: ".agents/skills/verify").appending(path: "launch-flags.md")
            try table.write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(
            try RepositoryFiles.text(of: launchFlagTablePath) == table,
            "\(launchFlagTablePath) is stale. Run: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests"
        )
    }

    @Test func launchFlagTableRendersOneRowPerFlagInTheOrderGiven() {
        let first = LaunchFlag(argument: "-FIRST_SCENARIO", meaning: "Seeds the first Block.")
        let second = LaunchFlag(argument: "-SECOND_SCENARIO", meaning: "Seeds the second Block.")
        let screen = LaunchFlag(argument: "-SCREEN", meaning: "Opens a screen.")
        let toggle = LaunchFlag(argument: "-SWITCH", meaning: "Turns a thing off.")

        let rows = launchFlagTable([toggle, second, screen], scenarios: [first, second], screens: [screen])
            .split(separator: "\n").suffix(3)

        #expect(
            Array(rows) == [
                "| `-SWITCH` | Switch | Turns a thing off. |",
                "| `-SECOND_SCENARIO` | Scenario 2 | Seeds the second Block. |",
                "| `-SCREEN` | Screen | Opens a screen. |"
            ]
        )
    }

#endif
