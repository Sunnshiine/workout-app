enum TestsWaitOnEventsNotClocksInComponent {
    static func taskSleepIsFlagged() async throws {
        try await Task.sleep(for: .milliseconds(10))
    }
}
