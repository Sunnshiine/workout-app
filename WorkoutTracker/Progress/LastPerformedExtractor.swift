import Foundation

struct LastPerformedRecord: Sendable, Equatable {
    var fullName: String
    var baseName: String
    var result: SetLog
    var performedOn: Date
    var source: String

    var entry: LastPerformedEntry {
        LastPerformedEntry(
            fullName: fullName,
            baseName: baseName,
            result: result,
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
                    guard let log = lastLoggedSet(in: exercise)?.setLog else { continue }

                    let performedOn = session.date ?? .distantPast
                    let candidate = LastPerformedCandidate(
                        fullName: exercise.name,
                        baseName: exercise.baseName,
                        result: log,
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
                    performedOn: $0.performedOn,
                    source: $0.source
                )
            }
    }

    private static func lastLoggedSet(in exercise: ParsedExercise) -> ParsedSet? {
        exercise.sets
            .filter { $0.state == .logged && $0.setLog != nil }
            .max { $0.index < $1.index }
    }
}

private struct LastPerformedCandidate {
    var fullName: String
    var baseName: String
    var result: SetLog
    var performedOn: Date
    var source: String
}
