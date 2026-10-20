import Foundation
import Testing

@testable import WorkoutTracker

@Suite struct MainLiftSheetLabelTests {
    @Test func theThreeLabelsTheCoachWritesResolve() {
        #expect(MainLift(sheetLabel: "Squat") == .squat)
        #expect(MainLift(sheetLabel: "Bench Press") == .bench)
        #expect(MainLift(sheetLabel: "Deadlift") == .deadlift)
    }

    @Test func labelMatchingIgnoresCase() {
        #expect(MainLift(sheetLabel: "BENCH PRESS") == .bench)
        #expect(MainLift(sheetLabel: "deadlift") == .deadlift)
    }

    /// The init trims, so a caller holding a raw cell does not have to remember to.
    @Test func surroundingWhitespaceIsIgnored() {
        #expect(MainLift(sheetLabel: "  Bench Press  ") == .bench)
        #expect(MainLift(sheetLabel: "\tDeadlift\n") == .deadlift)
    }

    @Test func aPartialOrDecoratedLabelNamesNoLift() {
        #expect(MainLift(sheetLabel: "Bench") == nil)
        #expect(MainLift(sheetLabel: "Squat (comp)") == nil)
        #expect(MainLift(sheetLabel: "OHP") == nil)
        #expect(MainLift(sheetLabel: "") == nil)
    }
}

@Suite struct MainLiftBaseNameMatchingTests {
    @Test func aBaseNameClaimsTheLiftItContains() {
        #expect(MainLift(claimedBy: "Back Squat") == .squat)
        #expect(MainLift(claimedBy: "Paused Bench Press") == .bench)
        #expect(MainLift(claimedBy: "Deficit Deadlift") == .deadlift)
    }

    @Test func aBaseNameContainingNoKeywordClaimsNothing() {
        #expect(MainLift(claimedBy: "RDL") == nil)
        #expect(MainLift(claimedBy: "") == nil)
    }

    @Test func matchPrecedenceResolvesSquatBeforeBenchBeforeDeadlift() {
        #expect(MainLift(claimedBy: "Squat Rack Bench Press") == .squat)
        #expect(MainLift(claimedBy: "Bench Press from Deadlift Blocks") == .bench)
    }
}
