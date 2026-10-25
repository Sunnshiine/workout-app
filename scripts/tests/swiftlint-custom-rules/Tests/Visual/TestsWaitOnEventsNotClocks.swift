import Foundation

enum TestsWaitOnEventsNotClocks {
    static func sleepInVisualTestsPasses() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }
}
