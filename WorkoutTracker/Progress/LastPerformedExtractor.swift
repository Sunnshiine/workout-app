import Foundation

enum LastPerformedExtractor {
    static func entries(from block: ParsedBlockModel) -> [LastPerformedEntry] {
        occurrences(from: block).map(LastPerformedEntry.init)
    }

    /// Every evidence-bearing (Exercise, Session) occurrence in the block, one canonical value each.
    ///
    /// Append-only (ADR-0012): unlike the former single-entry index, this does not collapse
    /// to the latest occurrence per name. Each Session an Exercise was performed in yields its
    /// own occurrence, keyed downstream by (`fullName`, `source`). Occurrences are emitted in
    /// Session order (week → day → Exercise), each carrying its already-derived display text.
    static func occurrences(from block: ParsedBlockModel) -> [LastPerformedOccurrence] {
        var occurrences: [LastPerformedOccurrence] = []

        for week in block.weeks {
            for session in week.days {
                for exercise in session.exercises {
                    guard let resultText = displayText(for: exercise) else { continue }

                    occurrences.append(
                        LastPerformedOccurrence(
                            fullName: exercise.name,
                            baseName: exercise.baseName,
                            resultText: resultText,
                            performedOn: session.date ?? .distantPast,
                            source: SessionCoordinate(
                                blockTab: block.tabName,
                                weekNumber: week.number,
                                dayNumber: session.dayNumber
                            ).storageValue
                        )
                    )
                }
            }
        }

        return occurrences
    }

    /// The Last Performed display text for one Exercise as logged in a Session (ADR-0012), or nil
    /// when the occurrence earns no entry.
    private static func displayText(for exercise: ParsedExercise) -> String? {
        let evidence = exercise.setLevelCompletionEvidence

        if exercise.hasSetLevelCompletionEvidence {
            return evidence.map(\.token).joined(separator: ", ")
        }

        if evidence.contains(.skipped) { return nil }
        return exercise.legacyLogAsCompletionEvidence
    }
}
