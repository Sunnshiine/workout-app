import Foundation

enum TestsWaitOnEventsNotClocks {
    static func sleepInUITestsPasses() {
        Thread.sleep(forTimeInterval: 0.5)
    }
}
