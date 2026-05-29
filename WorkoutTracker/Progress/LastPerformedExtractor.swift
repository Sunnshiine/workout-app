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

    static func records(from block: ParsedBlockModel) -> [LastPerformedRecord] {
        var latestByExercise: [String: LastPerformedCandidate] = [:]

        for week in block.weeks {
            for session in week.days {
                for exercise in session.exercises {
                    guard let evidence = lastPerformedEvidence(in: exercise) else { continue }

                    let performedOn = session.date ?? .distantPast
                    let candidate = LastPerformedCandidate(
                        fullName: exercise.name,
                        baseName: exercise.baseName,
                        result: evidence.result,
                        resultText: evidence.resultText,
                        performedOn: performedOn,
                        source: "\(block.tabName) · W\(week.number) D\(session.dayNumber)"
                    )

                    if let existing = latestByExercise[exercise.name] {
                        if candidate.performedOn >= existing.performedOn {
                            latestByExercise[exercise.name] = candidate
                        }
                    } else {
                        latestByExercise[exercise.name] = candidate
                    }
                }
            }
        }

        return latestByExercise.values
            .sorted { $0.fullName < $1.fullName }
            .map {
                LastPerformedRecord(
                    fullName: $0.fullName,
                    baseName: $0.baseName,
                    result: $0.result,
                    resultText: $0.resultText,
                    performedOn: $0.performedOn,
                    source: $0.source
                )
            }
    }

    private static func lastPerformedEvidence(in exercise: ParsedExercise) -> (result: SetLog?, resultText: String)? {
        let structuredLog = exercise.sets
            .filter { $0.state == .logged && $0.setLog != nil }
            .max { $0.index < $1.index }
            .flatMap(\.setLog)

        if let setLog = structuredLog {
            return (setLog, setLog.formatted)
        }

        guard let legacyLog = exercise.legacyLog else { return nil }
        return (nil, legacyLog)
    }
}

private struct LastPerformedCandidate {
    var fullName: String
    var baseName: String
    var result: SetLog?
    var resultText: String
    var performedOn: Date
    var source: String
}
