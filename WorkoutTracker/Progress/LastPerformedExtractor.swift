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
    /// Logged evidence beats skip beats the Legacy Log. An entry is earned only when at least one
    /// Set is actually Logged: a fully Skipped occurrence earns none even if a stale Legacy Log
    /// lingers on the Exercise, so an actively-Skipped Session never resurrects old free text. The
    /// Legacy Log is the fallback only for a truly empty occurrence (no set-level activity at all —
    /// the pre-structured-Set format).
    private static func displayText(for exercise: ParsedExercise) -> String? {
        let evidence = exercise.sets
            .sorted { $0.index < $1.index }
            .compactMap(\.lastPerformedEvidence)

        if evidence.contains(where: \.isLogged) {
            return evidence.map(\.token).joined(separator: ", ")
        }

        guard evidence.isEmpty, let legacyLog = exercise.legacyLog else { return nil }
        return legacyLog
    }
}

/// What one Set contributes to a Last Performed line (ADR-0012). Absence of evidence is `nil`:
/// a Pending Set and a legacy-completion placeholder Set (Logged with no content) contribute
/// nothing at all.
enum LastPerformedSetEvidence: Equatable, Sendable {
    /// A Structured Set Log formatted, or an Unstructured Set Log as the athlete entered it
    /// (never normalized — ADR-0005).
    case logged(String)
    case skipped

    /// The inline token this Set renders as, in Set order.
    var token: String {
        switch self {
        case .logged(let text): text
        case .skipped: SetLogToken.skipSentinel
        }
    }

    /// Only a Logged Set earns the occurrence an entry; a `skip` renders but does not.
    var isLogged: Bool {
        if case .logged = self { return true }
        return false
    }
}

extension ParsedSet {
    var lastPerformedEvidence: LastPerformedSetEvidence? {
        if let setLog { return .logged(setLog.formatted) }
        let text = unstructuredSetLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if state == .logged, !text.isEmpty { return .logged(text) }
        return state == .skipped ? .skipped : nil
    }
}
