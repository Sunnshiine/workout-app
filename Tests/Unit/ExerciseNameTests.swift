import Foundation
import Testing

@testable import WorkoutTracker

@Suite struct ExerciseNameTests {
    @Test func aCadencePrefixSplitsOffTheBaseName() {
        let name = ExerciseName(entered: "2-3:1:0 BB RDL")

        #expect(name.entered == "2-3:1:0 BB RDL")
        #expect(name.base == "BB RDL")
        #expect(name.cadence == "2-3:1:0")
    }

    @Test func aRangeInEveryCadencePhaseStillSplits() {
        let name = ExerciseName(entered: "2-3:1-2:0-1 Paused Squat")

        #expect(name.base == "Paused Squat")
        #expect(name.cadence == "2-3:1-2:0-1")
    }

    @Test func aNameWithNoCadenceIsItsOwnBaseName() {
        let name = ExerciseName(entered: "Lateral Raises")

        #expect(name.base == "Lateral Raises")
        #expect(name.cadence == nil)
    }

    @Test func numbersThatAreNotACadenceStayInTheBaseName() {
        #expect(ExerciseName(entered: "3:1 Row").base == "3:1 Row")
        #expect(ExerciseName(entered: "2-3:1:0").base == "2-3:1:0")
        #expect(ExerciseName(entered: "2-3:1:0BB RDL").cadence == nil)
    }

    /// Identity reads the entered name, so the same lift under two Cadences is two Exercises: a
    /// queued write and an `exercise_history` entry each keep addressing the one they named.
    @Test func theSameBaseNameUnderAnotherCadenceIsAnotherName() {
        let slow = ExerciseName(entered: "3:1:0 Back Squat")
        let fast = ExerciseName(entered: "1:0:0 Back Squat")

        #expect(slow.base == fast.base)
        #expect(slow != fast)
        #expect(Set([slow, fast]).count == 2)
        #expect(slow == ExerciseName(entered: "3:1:0 Back Squat"))
    }

    @Test func onlyASpellingDifferenceBeyondCaseCountsAsADifferentName() {
        let viewed = ExerciseName(entered: "Bench Press")

        #expect(!ExerciseName(entered: "bench press").differsBeyondCase(from: viewed))
        #expect(!ExerciseName(entered: "3:1:0 Bench Press").differsBeyondCase(from: viewed))
        #expect(ExerciseName(entered: "Comp BP").differsBeyondCase(from: viewed))
    }
}
