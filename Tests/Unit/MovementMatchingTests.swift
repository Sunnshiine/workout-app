import Foundation
import Testing

@testable import WorkoutTracker

// ADR-0013 calibration cases for Movement-level matching.

@Test func canonicalizeStripsCadenceLowercasesAndCollapses() {
    #expect(MovementMatching.canonicalize("2-3:1:0 BB RDL") == "barbell rdl")
    #expect(MovementMatching.canonicalize("Standing  Calf-Raise!") == "standing calf raise")
}

@Test func canonicalizeExpandsAbbreviationTable() {
    #expect(MovementMatching.canonicalize("Comp BP") == "competition bench press")
    #expect(MovementMatching.canonicalize("DB Bench") == "dumbbell bench")
    #expect(MovementMatching.canonicalize("BW Dips") == "bodyweight dips")
    // "rdl" is never spelled out — it stays.
    #expect(MovementMatching.canonicalize("RDL").contains("rdl"))
}

@Test func typosAndPluralsMergeAtThreshold() {
    #expect(MovementMatching.areSameMovement("Standing Calve Raises", "Standing Calf Raise"))
    #expect(MovementMatching.areSameMovement("Calf Raise", "Calf Raises"))
}

@Test func modifierWordsSplitMovements() {
    #expect(!MovementMatching.areSameMovement("Paused Bench Press", "Bench Press"))
}

@Test func abbreviationTableMergesCompBenchPress() {
    #expect(MovementMatching.areSameMovement("Comp BP", "Competition Bench Press"))
}

@Test func similarityIsNormalizedLevenshtein() {
    #expect(MovementMatching.similarity("kitten", "sitting") == 1 - 3.0 / 7.0)
    #expect(MovementMatching.similarity("abc", "abc") == 1)
}

// Tier-3 (Movement-level) ladder in the Last Performed lookup snapshot.

@Test func snapshotTierThreeFiresWhenExactAndBaseAreBlank() {
    // History carries the coach's misspelling; the viewed Exercise uses a different spelling.
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "Standing Calve Raises",
            baseName: "Standing Calve Raises",
            resultText: "25x12, 12",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])

    // Tiers 1 and 2 miss (byte-identical to today), tier 3 fires on the Movement.
    let match = snapshot.lookup(exerciseName: "Standing Calf Raise", baseName: "Standing Calf Raise")
    #expect(match?.resultText == "25x12, 12")
    #expect(match?.sourceText == "Block 27 · W1 D1")
    // The tier-3 line labels itself with the matched entry's own entered name.
    #expect(match?.matchedName == "Standing Calve Raises")
}

@Test func snapshotTierOneAndTwoCarryNoMatchedName() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            resultText: "185x7@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 26 · W3 D1"
        )
    ])

    // Tier 1: exact full name.
    #expect(snapshot.lookup(exerciseName: "2-3:1:0 BB RDL", baseName: "BB RDL")?.matchedName == nil)
    // Tier 2: exact base name.
    #expect(snapshot.lookup(exerciseName: "3:1:0 BB RDL", baseName: "BB RDL")?.matchedName == nil)
}

@Test func snapshotTierThreePicksNewestMatchingEntry() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "Standing Calve Raise",
            baseName: "Standing Calve Raise",
            resultText: "20x12",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 25 · W1 D1"
        ),
        LastPerformedEntry(
            fullName: "Standing Calve Raises",
            baseName: "Standing Calve Raises",
            resultText: "25x12",
            performedOn: Date(timeIntervalSinceReferenceDate: 300),
            source: "Block 27 · W1 D1"
        )
    ])

    let match = snapshot.lookup(exerciseName: "Standing Calf Raise", baseName: "Standing Calf Raise")
    #expect(match?.resultText == "25x12")
    #expect(match?.matchedName == "Standing Calve Raises")
}

@Test func snapshotTierThreeStaysBlankForUnrelatedMovements() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "Paused Bench Press",
            baseName: "Paused Bench Press",
            resultText: "225x5",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])

    // Modifier words split Movements — no tier-3 line for a bare "Bench Press".
    #expect(snapshot.lookup(exerciseName: "Bench Press", baseName: "Bench Press") == nil)
}
