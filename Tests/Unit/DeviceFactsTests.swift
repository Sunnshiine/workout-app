import Foundation
import Testing

@testable import WorkoutTracker

/// A record that names no phone, or no memory, cannot split latency by device.
@Test func theDeviceFactsNameThisMachineAndWhatTheProcessHolds() {
    let facts = DeviceFacts.current()
    let version = ProcessInfo.processInfo.operatingSystemVersion

    #expect(!facts.model.isEmpty)
    #expect(facts.model != "unknown")
    #expect(!facts.model.contains("\0"))
    #expect(facts.os == "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    #expect(facts.footprintMB > 0)
}
