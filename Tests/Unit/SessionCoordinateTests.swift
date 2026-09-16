import Foundation
import Testing

@testable import WorkoutTracker

@Test func coordinateEncodesTheCanonicalDedupKey() {
    let coordinate = SessionCoordinate(blockTab: "Block 27", weekNumber: 1, dayNumber: 1)

    // ADR-0012 keys the append-only history on this exact string: a change here re-appends every
    // stored entry on the next sync.
    #expect(coordinate.storageValue == "Block 27 · W1 D1")
    #expect(coordinate.sessionLabel == "W1 D1")
}

@Test func coordinateReadsBackEveryValueItWrites() {
    let written = [
        SessionCoordinate(blockTab: "Block 27", weekNumber: 1, dayNumber: 1),
        SessionCoordinate(blockTab: "Block 26", weekNumber: 4, dayNumber: 3),
        SessionCoordinate(blockTab: "Deload · Block 25", weekNumber: 12, dayNumber: 10)
    ]

    #expect(written.compactMap { SessionCoordinate(storageValue: $0.storageValue) } == written)
}

@Test func coordinateRefusesAValueWithoutTheCanonicalShape() {
    #expect(SessionCoordinate(storageValue: "W3 D2") == nil)
    #expect(SessionCoordinate(storageValue: "Block 27") == nil)
    #expect(SessionCoordinate(storageValue: "Block 27 · Week 1 Day 1") == nil)
    #expect(SessionCoordinate(storageValue: "Block 27 · W1") == nil)
}

@Test func labelsRenderANonConformingStoredValueWholeRatherThanDroppingIt() {
    #expect(SessionCoordinate.labels(forStoredValue: "Block 27 · W1 D1") == ("Block 27", "W1 D1"))
    #expect(SessionCoordinate.labels(forStoredValue: "W3 D2") == ("W3 D2", ""))
}

@Test func theSessionLabelIsTheSameWhetherOrNotABlockIsKnown() {
    let stored = SessionCoordinate(blockTab: "Block 27", weekNumber: 2, dayNumber: 3)

    #expect(SessionCoordinate.sessionLabel(weekNumber: 2, dayNumber: 3) == stored.sessionLabel)
}
