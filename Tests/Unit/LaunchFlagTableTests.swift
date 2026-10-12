import Foundation
import Testing

@testable import WorkoutTracker

#if DEBUG

    private let launchFlagTablePath = ".agents/skills/verify/launch-flags.md"

    private func launchFlagTable(_ flags: [LaunchFlag]) -> String {
        let header = """
            <!-- Generated from LaunchFlag in Sources/WorkoutTracker/Fixtures/LaunchFlag.swift. Do not edit.
                 Regenerate: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests -->
            # Launch flags

            With no Scenario flag, the fixture seeds a Partially Uploaded Block. When a launch passes more
            than one Scenario flag, the lowest Scenario number wins.

            | Flag | Kind | Meaning |
            | --- | --- | --- |

            """
        return header + flags.map { "| `\($0.rawValue)` | \(kind(of: $0)) | \($0.meaning) |\n" }.joined()
    }

    private func kind(of flag: LaunchFlag) -> String {
        if let priority = UITestLaunch.scenarioFlags.firstIndex(where: { $0.flag == flag }) {
            return "Scenario \(priority + 1)"
        }
        return UITestLaunch.screenFlags.contains(flag) ? "Screen" : "Switch"
    }

    @Test func launchFlagTableMatchesTheRegistry() throws {
        let table = launchFlagTable(LaunchFlag.allCases)
        if ProcessInfo.processInfo.environment["RECORD_LAUNCH_FLAGS"] == "1" {
            try table.write(to: RepositoryFiles.existingURL(of: launchFlagTablePath), atomically: true, encoding: .utf8)
        }
        #expect(
            try RepositoryFiles.text(of: launchFlagTablePath) == table,
            "\(launchFlagTablePath) is stale. Run: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests"
        )
    }

    @Test func launchFlagTableRendersOneRowPerFlagInTheOrderGiven() {
        let rows = launchFlagTable([.fullBlock, .settings]).split(separator: "\n").suffix(2)

        #expect(
            Array(rows) == [
                "| `-UITEST_FULL_BLOCK` | Scenario 5 | Seeds four Weeks of four Sessions, every one an Available Session. |",
                "| `-UITEST_SETTINGS` | Screen | Opens Settings in place of the Session screen. |"
            ]
        )
    }

#endif
