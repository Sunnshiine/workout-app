import Foundation
import Testing

@testable import WorkoutTracker

@Test func extractsLastPerformedEntriesFromLoggedParsedSets() throws {
    let olderDate = try #require(DateFormatter.testDate.date(from: "5/1/2026"))
    let newerDate = try #require(DateFormatter.testDate.date(from: "5/8/2026"))
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: olderDate,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            loggedSet(index: 0, weight: 185, reps: 5, rpe: 7),
                            loggedSet(index: 1, weight: 195, reps: 5, rpe: 8)
                        ]
                    ),
                    exercise("Bench Press", sets: [loggedSet(index: 0, weight: 155, reps: 6, rpe: 7)])
                ]
            ),
            week(
                2,
                date: newerDate,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            pendingSet(index: 0),
                            loggedSet(index: 1, weight: 205, reps: 4, rpe: 8)
                        ]
                    ),
                    exercise("Deadlift", sets: [skippedSet(index: 0)])
                ]
            )
        ]
    )

    let entries = LastPerformedExtractor.entries(from: block)

    #expect(entries.count == 2)
    let squat = try #require(entries.first { $0.fullName == "Squat" })
    #expect(squat.baseName == "Squat")
    #expect(squat.result == SetLog(weight: .pounds(205), reps: 4, rpe: 8))
    #expect(squat.performedOn == newerDate)
    #expect(squat.source == "Block 27 · W2 D1")

    let bench = try #require(entries.first { $0.fullName == "Bench Press" })
    #expect(bench.result == SetLog(weight: .pounds(155), reps: 6, rpe: 7))
    #expect(bench.source == "Block 27 · W1 D1")
}

@Test func extractorReturnsEmptyArrayWithoutLoggedSets() {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            pendingSet(index: 0),
                            skippedSet(index: 1)
                        ]
                    )
                ]
            )
        ]
    )

    #expect(LastPerformedExtractor.entries(from: block).isEmpty)
}

private func week(_ number: Int, date: Date?, exercises: [ParsedExercise]) -> ParsedWeek {
    ParsedWeek(
        number: number,
        days: [
            ParsedSession(dayNumber: 1, date: date, exercises: exercises)
        ]
    )
}

private func exercise(_ name: String, sets: [ParsedSet]) -> ParsedExercise {
    ParsedExercise(name: name, baseName: name, cadence: nil, coachNote: nil, sets: sets)
}

private func loggedSet(index: Int, weight: Double, reps: Int, rpe: Double) -> ParsedSet {
    ParsedSet(
        index: index,
        prescribedReps: "\(reps)",
        prescribedLoad: "RPE \(Int(rpe))",
        percentOneRM: nil,
        setLog: SetLog(weight: .pounds(weight), reps: reps, rpe: rpe)
    )
}

private func pendingSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil)
}

private func skippedSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .skipped)
}

extension DateFormatter {
    fileprivate static let testDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
