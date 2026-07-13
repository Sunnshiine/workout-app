import Foundation
import Testing

@testable import WorkoutTracker

// The unified two-tier-plus-Movement ladder and the newest-wins dedup, stated once on the
// in-memory snapshot (PRD #330). `lookup(for:)` derives the Cadence-stripped base name itself,
// so callers pass only the exercise name.

@Test func lookupForDerivesBaseNameByCadenceStripping() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            resultText: "185x7@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 26 · W3 D1"
        )
    ])

    // Tier 1: the exact full name, Cadence included.
    #expect(snapshot.lookup(for: "2-3:1:0 BB RDL")?.resultText == "185x7@7")
    // Tier 2: a different Cadence resolves via the internally-derived base name — the caller
    // never spells out "BB RDL".
    let fallback = snapshot.lookup(for: "3:1:0 BB RDL")
    #expect(fallback?.resultText == "185x7@7")
    #expect(fallback?.sourceText == "Block 26 · W3 D1")
    #expect(fallback?.matchedName == nil)
    // No history for the Movement at all.
    #expect(snapshot.lookup(for: "Bench Press") == nil)
}

@Test func newestWinsForTheSameFullName() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "205x5@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 26 · W4 D1"
        ),
        LastPerformedEntry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "225x5@8",
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 27 · W1 D1"
        )
    ])

    let match = snapshot.lookup(for: "Bench Press")
    #expect(match?.resultText == "225x5@8")
    #expect(match?.sourceText == "Block 27 · W1 D1")
}

@Test func newestWinsForTheSameBaseNameAcrossCadences() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "1:0:1 BB RDL",
            baseName: "BB RDL",
            resultText: "175x7@6",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 25 · W4 D1"
        ),
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            resultText: "185x7@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 26 · W3 D1"
        )
    ])

    // A third, unseen Cadence falls back to the base name and picks the newest Session.
    let match = snapshot.lookup(for: "5:1:0 BB RDL")
    #expect(match?.resultText == "185x7@7")
    #expect(match?.sourceText == "Block 26 · W3 D1")
}
