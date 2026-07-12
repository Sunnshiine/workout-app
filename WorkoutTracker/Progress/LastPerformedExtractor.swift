import Foundation

struct LastPerformedRecord: Sendable, Equatable {
    var fullName: String
    var baseName: String
    var result: SetLog?
    var resultText: String
    var performedOn: Date
    var source: String

    var entry: LastPerformedEntry {
        if let result {
            return LastPerformedEntry(
                fullName: fullName,
                baseName: baseName,
                result: result,
                performedOn: performedOn,
                source: source
            )
        }
        return LastPerformedEntry(
            fullName: fullName,
            baseName: baseName,
            resultText: resultText,
            performedOn: performedOn,
            source: source
        )
    }
}

enum LastPerformedExtractor {
    static func entries(from block: ParsedBlockModel) -> [LastPerformedEntry] {
        records(from: block).map(\.entry)
    }

    /// Every evidence-bearing (Exercise, Session) occurrence in the block, one record each.
    ///
    /// Append-only (ADR-0012): unlike the former single-entry index, this does not collapse
    /// to the latest occurrence per name. Each Session an Exercise was performed in yields its
    /// own record, keyed downstream by (`fullName`, `source`). Records are emitted in Session
    /// order (week → day → Exercise).
    static func records(from block: ParsedBlockModel) -> [LastPerformedRecord] {
        var records: [LastPerformedRecord] = []

        for week in block.weeks {
            for session in week.days {
                for exercise in session.exercises {
                    guard let evidence = lastPerformedEvidence(in: exercise) else { continue }

                    records.append(
                        LastPerformedRecord(
                            fullName: exercise.name,
                            baseName: exercise.baseName,
                            result: evidence.result,
                            resultText: evidence.resultText,
                            performedOn: session.date ?? .distantPast,
                            source: "\(block.tabName) · W\(week.number) D\(session.dayNumber)"
                        )
                    )
                }
            }
        }

        return records
    }

    /// Completion evidence for one Exercise as logged in a Session (ADR-0012).
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
    private static func lastPerformedEvidence(in exercise: ParsedExercise) -> (result: SetLog?, resultText: String)? {
        var tokens: [String] = []
        var structuredLogs: [SetLog] = []
        var hasLoggedEvidence = false

        for set in exercise.sets.sorted(by: { $0.index < $1.index }) {
            if let setLog = set.setLog {
                tokens.append(setLog.formatted)
                structuredLogs.append(setLog)
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
            // Preserve a lone structured Set Log as a typed result — byte-identical to before —
            // only when the whole entry is exactly that one log (no skips, no unstructured text).
            let result = (tokens.count == 1 && structuredLogs.count == 1) ? structuredLogs.first : nil
            return (result, tokens.joined(separator: ", "))
        }

        // Only a truly empty occurrence (no logged, unstructured, or `skip` tokens) falls back to
        // the Legacy Log. A non-empty `tokens` with no logged evidence means the Session was
        // actively Skipped, which earns no entry.
        guard tokens.isEmpty, let legacyLog = exercise.legacyLog else { return nil }
        return (nil, legacyLog)
    }
}
