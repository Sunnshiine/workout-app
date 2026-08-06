import Foundation
import Testing

@testable import WorkoutTracker

// The Movement-level history query behind the Exercise History sheet (ADR-0012 / ADR-0013).

private func historyEntry(
    fullName: String,
    baseName: String,
    resultText: String,
    source: String,
    daysAgo: Int
) -> LastPerformedEntry {
    LastPerformedEntry(
        fullName: fullName,
        baseName: baseName,
        resultText: resultText,
        performedOn: Date(timeIntervalSince1970: 1_700_000_000) - Double(daysAgo) * 86_400,
        source: source
    )
}

@Test func historyQueryReturnsMovementMatchesNewestFirst() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        historyEntry(fullName: "Bench Press", baseName: "Bench Press", resultText: "185x5@8",
                     source: "Block 26 · W1 D1", daysAgo: 30),
        historyEntry(fullName: "bench press", baseName: "bench press", resultText: "190x5@8",
                     source: "Block 27 · W1 D1", daysAgo: 5),
        // Fuzzy spelling variant of the same Movement.
        historyEntry(fullName: "Bench Presss", baseName: "Bench Presss", resultText: "195x5@8",
                     source: "Block 27 · W2 D1", daysAgo: 1),
        // A different Movement must not appear.
        historyEntry(fullName: "Paused Bench Press", baseName: "Paused Bench Press", resultText: "155x5@8",
                     source: "Block 27 · W2 D1", daysAgo: 2),
    ])

    let history = snapshot.history(baseName: "Bench Press")

    #expect(history.map(\.resultText) == ["195x5@8", "190x5@8", "185x5@8"])
    #expect(history.allSatisfy { $0.baseName != "Paused Bench Press" })
}

@Test func historyQueryProjectsDisplayResultTextAndSource() throws {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        LastPerformedEntry(
            fullName: "3-0:1:0 Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(315), reps: 3, rpe: 8),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 27 · W1 D1"
        )
    ])

    let entry = try #require(snapshot.history(baseName: "Squat").first)
    #expect(entry.fullName == "3-0:1:0 Squat")
    #expect(entry.resultText == "315x3@8")
    #expect(entry.source == "Block 27 · W1 D1")
}

@Test func historyQueryIsEmptyForUnknownMovement() {
    let snapshot = LastPerformedLookupSnapshot(entries: [
        historyEntry(fullName: "Deadlift", baseName: "Deadlift", resultText: "405x3@8",
                     source: "Block 27 · W1 D1", daysAgo: 1)
    ])

    #expect(snapshot.history(baseName: "Overhead Press").isEmpty)
}
