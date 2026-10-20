import Foundation
import Testing

@testable import WorkoutTracker

// ADR-0013 calibration cases for Movement-level matching.

@Test func canonicalizeLowercasesAndCollapses() {
    #expect(MovementMatching.canonicalize("BB RDL") == "barbell rdl")
    #expect(MovementMatching.canonicalize("Standing  Calf-Raise!") == "standing calf raise")
}

@Test func aCadencePrefixNeverSplitsAMovement() {
    #expect(ExerciseName(entered: "2-3:1:0 BB RDL").isSameMovement(as: "BB RDL"))
    #expect(ExerciseName(entered: "0:2:0 Hamstring Curl").isSameMovement(as: "3:1:0 Hamstring Curl"))
}

@Test func canonicalizeExpandsAbbreviationTable() {
    #expect(MovementMatching.canonicalize("Comp BP") == "competition bench press")
    #expect(MovementMatching.canonicalize("DB Bench") == "dumbbell bench")
    #expect(MovementMatching.canonicalize("BW Dips") == "bodyweight dips")
    // "rdl" is never spelled out — it stays.
    #expect(MovementMatching.canonicalize("RDL").contains("rdl"))
}

@Test func typosAndPluralsMergeAtThreshold() {
    #expect(ExerciseName(entered: "Standing Calve Raises").isSameMovement(as: "Standing Calf Raise"))
    #expect(ExerciseName(entered: "Calf Raise").isSameMovement(as: "Calf Raises"))
}

@Test func modifierWordsSplitMovements() {
    #expect(!ExerciseName(entered: "Paused Bench Press").isSameMovement(as: "Bench Press"))
}

@Test func abbreviationTableMergesCompBenchPress() {
    #expect(ExerciseName(entered: "Comp BP").isSameMovement(as: "Competition Bench Press"))
}

@Test func similarityIsNormalizedLevenshtein() {
    #expect(MovementMatching.similarity("kitten", "sitting") == 1 - 3.0 / 7.0)
    #expect(MovementMatching.similarity("abc", "abc") == 1)
}

// Choice Exercises (#428): "A or B" is the same Movement as anything either option is.

@Test func aChoiceMatchesEachOptionWithItsSharedWords() {
    let choice = ExerciseName(entered: "Incline Machine or DB Bench Press")
    #expect(choice.isSameMovement(as: "Incline DB Bench Press"))
    #expect(choice.isSameMovement(as: "Incline Machine Bench Press"))
    #expect(choice.isSameMovement(as: "Incline Machine Press"))
    #expect(!choice.isSameMovement(as: "Bench Press"))
}

@Test func aChoiceOfWholeNamesMatchesEachName() {
    let choice = ExerciseName(entered: "Leg Press or Hack Squat")
    #expect(choice.isSameMovement(as: "Leg Press"))
    #expect(choice.isSameMovement(as: "Hack Squat"))
}

@Test func aChoiceOfThreeMatchesItsMiddleOptionWithTheSharedWords() {
    let choice = ExerciseName(entered: "Cable or DB or Machine Lateral Raise")
    #expect(choice.isSameMovement(as: "DB Lateral Raise"))
    #expect(choice.isSameMovement(as: "Cable Lateral Raise"))
    #expect(choice.isSameMovement(as: "Machine Lateral Raise"))
    #expect(!choice.isSameMovement(as: "Lateral Raise"))
}

@Test func aLoggedChoiceMatchesAViewedOption() {
    #expect(ExerciseName(entered: "Incline DB Bench Press").isSameMovement(as: "Incline Machine or DB Bench Press"))
    #expect(ExerciseName(entered: "Hack Squat").isSameMovement(as: "Leg Press or Hack Squat"))
}

@Test func twoChoicesMatchWhenAnyOptionsMatch() {
    #expect(ExerciseName(entered: "Cable or DB Lateral Raise").isSameMovement(as: "DB or Machine Lateral Raise"))
    #expect(!ExerciseName(entered: "Cable or DB Lateral Raise").isSameMovement(as: "Leg Press or Hack Squat"))
}

@Test func theChoiceWordSplitsRegardlessOfCaseAndSpacing() {
    #expect(ExerciseName(entered: "Leg Press  OR   Hack Squat").isSameMovement(as: "Hack Squat"))
    #expect(ExerciseName(entered: "3:1:0 Leg Press Or Hack Squat").isSameMovement(as: "Leg Press"))
}

@Test func orInsideAWordIsNotAChoice() {
    #expect(!ExerciseName(entered: "Floor Press").isSameMovement(as: "Press"))
    #expect(!ExerciseName(entered: "Good Morning").isSameMovement(as: "Good"))
    #expect(!ExerciseName(entered: "Or Press").isSameMovement(as: "Press"))
}

// An option matches whatever the same name standing alone matches, so a choice inherits each
// option's existing over-matches (ADR-0013, amended for #428). These pin the two known ones.

@Test func aChoiceInheritsHackSquatMatchingBackSquat() {
    #expect(ExerciseName(entered: "Hack Squat").isSameMovement(as: "Back Squat"))
    #expect(ExerciseName(entered: "Leg Press or Hack Squat").isSameMovement(as: "Back Squat"))
    #expect(ExerciseName(entered: "Back Squat").isSameMovement(as: "Leg Press or Hack Squat"))
}

@Test func aChoiceInheritsItsBareOptionMatchingFlatDBBenchPress() {
    #expect(ExerciseName(entered: "DB Bench Press").isSameMovement(as: "Flat DB Bench Press"))
    #expect(ExerciseName(entered: "Incline Machine or DB Bench Press").isSameMovement(as: "Flat DB Bench Press"))
}

// Tier-3 (Movement-level) ladder in the Last Performed lookup snapshot.

@Test func snapshotTierThreeFindsAnOptionLoggedUnderItsOwnName() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            exerciseName: "Incline DB Bench Press",
            resultText: "185x5@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 28 · W1 D1"
        )
    ])

    let match = snapshot.lookup(for: "Incline Machine or DB Bench Press")
    #expect(match?.resultText == "185x5@7")
    #expect(match?.matchedName == "Incline DB Bench Press")
}

@Test func snapshotTierThreeFindsAChoiceLoggedUnderTheChoiceName() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            exerciseName: "Incline Machine or DB Bench Press",
            resultText: "185x5@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 28 · W1 D1"
        )
    ])

    let match = snapshot.lookup(for: "Incline DB Bench Press")
    #expect(match?.resultText == "185x5@7")
    #expect(match?.matchedName == "Incline Machine or DB Bench Press")
}

@Test func snapshotTierThreeFiresWhenExactAndBaseAreBlank() {
    // History carries the coach's misspelling; the viewed Exercise uses a different spelling.
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            exerciseName: "Standing Calve Raises",
            resultText: "25x12, 12",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])

    // Tiers 1 and 2 miss (byte-identical to today), tier 3 fires on the Movement.
    let match = snapshot.lookup(for: "Standing Calf Raise")
    #expect(match?.resultText == "25x12, 12")
    #expect(match?.sourceText == "Block 27 · W1 D1")
    // The tier-3 line labels itself with the matched entry's own entered name.
    #expect(match?.matchedName == "Standing Calve Raises")
}

@Test func snapshotTierOneAndTwoCarryNoMatchedName() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            exerciseName: "2-3:1:0 BB RDL",
            resultText: "185x7@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 26 · W3 D1"
        )
    ])

    // Tier 1: exact full name.
    #expect(snapshot.lookup(for: "2-3:1:0 BB RDL")?.matchedName == nil)
    // Tier 2: exact base name.
    #expect(snapshot.lookup(for: "3:1:0 BB RDL")?.matchedName == nil)
}

@Test func snapshotTierThreePicksNewestMatchingEntry() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            exerciseName: "Standing Calve Raise",
            resultText: "20x12",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 25 · W1 D1"
        ),
        LastPerformedEntry(
            exerciseName: "Standing Calve Raises",
            resultText: "25x12",
            performedOn: Date(timeIntervalSinceReferenceDate: 300),
            source: "Block 27 · W1 D1"
        )
    ])

    let match = snapshot.lookup(for: "Standing Calf Raise")
    #expect(match?.resultText == "25x12")
    #expect(match?.matchedName == "Standing Calve Raises")
}

@Test func snapshotTierThreeStaysBlankForUnrelatedMovements() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            exerciseName: "Paused Bench Press",
            resultText: "225x5",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])

    // Modifier words split Movements — no tier-3 line for a bare "Bench Press".
    #expect(snapshot.lookup(for: "Bench Press") == nil)
}
