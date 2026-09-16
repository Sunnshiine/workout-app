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
        #expect(MainLift(matchingBaseName: "Back Squat") == .squat)
        #expect(MainLift(matchingBaseName: "Paused Bench Press") == .bench)
        #expect(MainLift(matchingBaseName: "Deficit Deadlift") == .deadlift)
    }

    @Test func aBaseNameContainingNoKeywordClaimsNothing() {
        #expect(MainLift(matchingBaseName: "RDL") == nil)
        #expect(MainLift(matchingBaseName: "") == nil)
    }

    @Test func matchPrecedenceResolvesSquatBeforeBenchBeforeDeadlift() {
        #expect(MainLift(matchingBaseName: "Squat Rack Bench Press") == .squat)
        #expect(MainLift(matchingBaseName: "Bench Press from Deadlift Blocks") == .bench)
    }
}
