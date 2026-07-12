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

    private static func lastPerformedEvidence(in exercise: ParsedExercise) -> (result: SetLog?, resultText: String)? {
        let structuredLogs = exercise.sets
            .filter { $0.state == .logged }
            .sorted { $0.index < $1.index }
            .compactMap(\.setLog)

        if !structuredLogs.isEmpty {
            let resultText = structuredLogs.map(\.formatted).joined(separator: ", ")
            return (structuredLogs.count == 1 ? structuredLogs.first : nil, resultText)
        }

        guard let legacyLog = exercise.legacyLog else { return nil }
        return (nil, legacyLog)
    }
}
