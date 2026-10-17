import Foundation

/// An Exercise History entry's identity, an Exercise's full name in one Session (ADR-0012).
struct LastPerformedEntryKey: Hashable, Sendable {
    let fullName: String
    /// The performed-in Session as a `SessionCoordinate.storageValue`.
    let source: String
}

enum LastPerformedExtractor {
    /// Every (Exercise, Session) in the block that earns no entry, because no Exercise of that name
    /// in that Session holds completion evidence. Two same-named Exercises in one Session share a
    /// key (#813), so one with evidence keeps the key off this list.
    static func keysWithoutEntry(from block: ParsedBlockModel) -> Set<LastPerformedEntryKey> {
        var keys: Set<LastPerformedEntryKey> = []
        forEachExercise(in: block) { exercise, _, source in
            keys.insert(LastPerformedEntryKey(fullName: exercise.exerciseName.entered, source: source))
        }
        return keys.subtracting(occurrences(from: block).map(\.key))
    }

    static func entries(from block: ParsedBlockModel) -> [LastPerformedEntry] {
        occurrences(from: block).map(LastPerformedEntry.init)
    }

    /// Every evidence-bearing (Exercise, Session) occurrence in the block, one canonical value each.
    ///
    /// Append-only (ADR-0012): unlike the former single-entry index, this does not collapse
    /// to the latest occurrence per name. Each Session an Exercise was performed in yields its
    /// own occurrence, keyed downstream by (Entered Name, `source`). Occurrences are emitted in
    /// Session order (week → day → Exercise), each carrying its already-derived display text.
    static func occurrences(from block: ParsedBlockModel) -> [LastPerformedOccurrence] {
        var occurrences: [LastPerformedOccurrence] = []
        forEachExercise(in: block) { exercise, session, source in
            guard let resultText = displayText(for: exercise) else { return }

            occurrences.append(
                LastPerformedOccurrence(
                    exerciseName: exercise.exerciseName,
                    resultText: resultText,
                    performedOn: session.date ?? .distantPast,
                    source: source
                )
            )
        }
        return occurrences
    }

    /// Visits every Exercise in Session order (week → day → Exercise) with its Session's `source`.
    private static func forEachExercise(
        in block: ParsedBlockModel,
        _ body: (ParsedExercise, ParsedSession, String) -> Void
    ) {
        for week in block.weeks {
            for session in week.days {
                let source = SessionCoordinate(blockTab: block.tabName, address: week.address(of: session)).storageValue
                for exercise in session.exercises {
                    body(exercise, session, source)
                }
            }
        }
    }

    /// The Last Performed display text for one Exercise as logged in a Session (ADR-0012), or nil
    /// when the occurrence earns no entry.
    private static func displayText(for exercise: ParsedExercise) -> String? {
        let evidence = exercise.setLevelCompletionEvidence
        if let resultText = evidence.resultText { return resultText }
        if evidence.contains(.skipped) { return nil }
        return exercise.legacyLogAsCompletionEvidence
    }
}
