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
                            source: "\(block.tabName) · W\(week.number) D\(session.dayNumber)"
                        )
                    )
                }
            }
        }

        return occurrences
    }

    /// The Last Performed display text for one Exercise as logged in a Session (ADR-0012), or nil
    /// when the occurrence earns no entry.
    ///
    /// Structured Set Logs, Unstructured Set Logs, and `skip` markers all render inline in Set
    /// order: a structured log is its formatted string, an Unstructured Set Log is the raw entered
    /// text (never normalized — ADR-0005), a Skipped Set is the `skip` sentinel. Pending Sets and
    /// legacy-completion placeholder Sets (Logged with no content) carry no evidence and drop out.
    ///
    /// An entry is earned only when at least one Set is actually Logged: a fully Skipped occurrence
    /// (only `skip` tokens, no logged Set) earns none — even if a stale Legacy Log lingers on the
    /// Exercise. The Legacy Log is the fallback only for a truly empty occurrence (no set-level
    /// activity at all — the pre-structured-Set format), so an actively-Skipped Session never
    /// resurrects old free text as evidence.
    private static func displayText(for exercise: ParsedExercise) -> String? {
        var tokens: [String] = []
        var hasLoggedEvidence = false

        for set in exercise.sets.sorted(by: { $0.index < $1.index }) {
            if let setLog = set.setLog {
                tokens.append(setLog.formatted)
                hasLoggedEvidence = true
            } else if set.state == .logged,
                let text = set.unstructuredSetLog?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty {
                tokens.append(text)
                hasLoggedEvidence = true
            } else if set.state == .skipped {
                tokens.append(SetLogToken.skipSentinel)
            }
        }

        if hasLoggedEvidence {
            return tokens.joined(separator: ", ")
        }

        // Only a truly empty occurrence (no logged, unstructured, or `skip` tokens) falls back to
        // the Legacy Log. A non-empty `tokens` with no logged evidence means the Session was
        // actively Skipped, which earns no entry.
        guard tokens.isEmpty, let legacyLog = exercise.legacyLog else { return nil }
        return legacyLog
    }
}
