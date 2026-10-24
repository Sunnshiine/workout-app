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

    private func launchFlagTable(_ flags: [LaunchFlag]) -> String {
        let alone = flags.filter { $0.actsWithoutFixture && $0 != .fixture }.map { "`\($0.argument)`" }
        let fixtureRule =
            alone.isEmpty
            ? "Every flag acts only when the launch also passes `\(LaunchFlag.fixture.argument)`."
            : "Every flag but \(listed(alone)) acts only when the launch also passes `\(LaunchFlag.fixture.argument)`."
        let header = """
            <!-- Generated from LaunchFlag in Sources/WorkoutTracker/Fixtures/LaunchFlag.swift. Do not edit.
                 Regenerate: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests -->
            # Launch flags

            With no Scenario flag, the fixture seeds a Partially Uploaded Block parsed from the
            `partial-upload` workbook scenario, the cells `workout init --scenario partial-upload` also
            reads. When a launch passes more than one Scenario flag, the lowest Scenario number wins.
            A Value flag takes the argument after it, and a launch that leaves the value out stops.
            \(fixtureRule)

            | Flag | Kind | Meaning |
            | --- | --- | --- |

            """
        let scenarios = flags.filter { if case .scenario = $0.kind { true } else { false } }
        return header
            + flags.map { flag in
                let kind =
                    switch flag.kind {
                    case .switch: "Switch"
                    case .screen: "Screen"
                    case .scenario: "Scenario \((scenarios.firstIndex(of: flag) ?? 0) + 1)"
                    case .value: "Value"
                    }
                let needs = flag.needs.map { " Acts only with `\($0.argument)`, and a launch without it stops." }.joined()
                return "| `\(flag.argument)` | \(kind) | \(flag.meaning)\(needs) |\n"
            }.joined()
    }

    @Test func launchFlagTableMatchesTheRegistry() throws {
        let table = launchFlagTable(LaunchFlag.all)
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
        let first = LaunchFlag(argument: "-FIRST_SCENARIO", kind: .scenario(.fullBlock), meaning: "Seeds the first Block.")
        let second = LaunchFlag(argument: "-SECOND_SCENARIO", kind: .scenario(.longSession), meaning: "Seeds the second Block.")
        let screen = LaunchFlag(argument: "-SCREEN", kind: .screen, meaning: "Opens a screen.")
        let toggle = LaunchFlag(argument: "-SWITCH", meaning: "Turns a thing off.")
        let value = LaunchFlag(argument: "-VALUE", kind: .value, meaning: "Takes a name.", needs: [toggle])

        let rows = launchFlagTable([toggle, first, second, screen, value]).split(separator: "\n").suffix(5)

        #expect(
            Array(rows) == [
                "| `-SWITCH` | Switch | Turns a thing off. |",
                "| `-FIRST_SCENARIO` | Scenario 1 | Seeds the first Block. |",
                "| `-SECOND_SCENARIO` | Scenario 2 | Seeds the second Block. |",
                "| `-SCREEN` | Screen | Opens a screen. |",
                "| `-VALUE` | Value | Takes a name. Acts only with `-SWITCH`, and a launch without it stops. |"
            ]
        )
    }

#endif
