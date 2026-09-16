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

    /// Whole-cell equality, not substring: the label column says "Bench Press" or it names no lift.
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

    /// Declaration order is the precedence, so an ambiguous name resolves squat before bench
    /// before deadlift. Changing the case order changes which Training Max an athlete sees.
    @Test func declarationOrderIsThePrecedence() {
        #expect(MainLift(matchingBaseName: "Squat Rack Bench Press") == .squat)
        #expect(MainLift(matchingBaseName: "Bench Press from Deadlift Blocks") == .bench)
    }
}
