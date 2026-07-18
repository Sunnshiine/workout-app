import Foundation
import Testing

@testable import WorkoutTracker

@Test func buildIdentityReadsStampedKeysFromInfoDictionary() {
    let identity = BuildIdentity(info: [
        "CFBundleShortVersionString": "0.372",
        "CFBundleVersion": "7",
        "GitCommit": "6aba617",
        "PRNumber": "372",
        "Branch": "agent/issue-374",
        "RunNumber": "7",
    ])

    #expect(identity.version == "0.372")
    #expect(identity.build == "7")
    #expect(identity.commit == "6aba617")
    #expect(identity.prNumber == "372")
    #expect(identity.branch == "agent/issue-374")
    #expect(identity.runNumber == "7")
    #expect(identity.isStamped)
}

@Test func buildIdentityCompactLineJoinsPresentSegments() {
    let identity = BuildIdentity(info: [
        "CFBundleShortVersionString": "0.372",
        "CFBundleVersion": "7",
        "GitCommit": "6aba617",
        "PRNumber": "372",
        "Branch": "agent/issue-374",
        "RunNumber": "7",
    ])

    #expect(identity.compactLine == "0.372 (7) · 6aba617 · PR #372")
}

@Test func buildIdentityStableBuildHidesPRSegment() {
    // Stable TestFlight builds stamp an empty PRNumber; the PR segment hides itself.
    let identity = BuildIdentity(info: [
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "42",
        "GitCommit": "deadbee",
        "PRNumber": "",
        "Branch": "main",
        "RunNumber": "42",
    ])

    #expect(identity.compactLine == "1.0 (42) · deadbee")
    #expect(identity.prNumber == nil)
    #expect(identity.isStamped)
}

@Test func buildIdentityLocalBuildAppendsLocalBuildAndFallsBackOnVersion() {
    let identity = BuildIdentity(info: [:])

    #expect(identity.version == "0.0")
    #expect(identity.build == "0")
    #expect(identity.commit == nil)
    #expect(identity.isStamped == false)
    #expect(identity.compactLine == "0.0 (0) · local build")
}

@Test func buildIdentityCopyTextListsPresentFields() {
    let identity = BuildIdentity(info: [
        "CFBundleShortVersionString": "0.372",
        "CFBundleVersion": "7",
        "GitCommit": "6aba617",
        "PRNumber": "372",
        "Branch": "agent/issue-374",
        "RunNumber": "7",
    ])

    #expect(identity.copyText == """
    Version: 0.372 (7)
    Commit: 6aba617
    Branch: agent/issue-374
    PR: #372
    Run: 7
    """)
}

@Test func buildIdentityCopyTextForLocalBuildNotesMissingStamp() {
    let identity = BuildIdentity(info: [
        "CFBundleShortVersionString": "0.0",
        "CFBundleVersion": "1",
    ])

    #expect(identity.copyText == """
    Version: 0.0 (1)
    Local build (no CI stamp)
    """)
}
