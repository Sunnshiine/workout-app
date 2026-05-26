import Foundation
import SwiftData

enum WorkoutLoggingError: Error, Equatable {
    case missingExercise
    case missingSession
    case missingWeek
    case missingBlock
}

@MainActor
@Observable
final class WorkoutStore {
    private(set) var block: Block?
    private(set) var displayedSession: Session?

    private let context: ModelContext
    private let tracker = SessionProgressTracker()

    init(context: ModelContext) { self.context = context }

    var currentSession: Session? { block.flatMap { tracker.currentSession(in: $0) } }
    var isViewingLiveEdge: Bool { displayedSession?.persistentModelID == currentSession?.persistentModelID }

    func reload() {
        block = try? context.fetch(FetchDescriptor<Block>()).first
        displayedSession = currentSession
    }

    func show(week: Int, day: Int) {
        displayedSession = block?.weeks.first { $0.number == week }?.sessions.first { $0.dayNumber == day }
    }

    // MARK: - Optimistic Logging

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        let previousValue = set.setLog?.formatted ?? ""
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = log
        set.state = .logged
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: log.formatted,
            expectedCurrentValue: previousValue
        )
        if isFinalSet(set) {
            try enqueue(
                for: set,
                column: .lastSetRPE,
                operation: .upsert,
                valueToWrite: rpeLabel(log.rpe),
                expectedCurrentValue: previousRPE
            )
        }
        try context.save()
    }

    func skip(_ set: ExerciseSet) throws {
        let previousValue = set.setLog?.formatted ?? (set.state == .skipped ? "skip" : "")
        set.setLog = nil
        set.state = .skipped
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: "skip",
            expectedCurrentValue: previousValue
        )
        try context.save()
    }

    func deleteLog(for set: ExerciseSet) throws {
        let previousValue = set.setLog?.formatted ?? (set.state == .skipped ? "skip" : "")
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = nil
        set.state = .pending
        try enqueue(
            for: set,
            column: .notes,
            operation: .delete,
            valueToWrite: nil,
            expectedCurrentValue: previousValue
        )
        if isFinalSet(set), !previousRPE.isEmpty {
            try enqueue(
                for: set,
                column: .lastSetRPE,
                operation: .delete,
                valueToWrite: nil,
                expectedCurrentValue: previousRPE
            )
        }
        try context.save()
    }

    // MARK: - Private Helpers

    private func enqueue(
        for set: ExerciseSet,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) throws {
        guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
        guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
        guard let week = session.week else { throw WorkoutLoggingError.missingWeek }
        guard let block = week.block else { throw WorkoutLoggingError.missingBlock }
        context.insert(
            PendingWrite(
                blockTab: block.tabName,
                week: week.number,
                day: session.dayNumber,
                exerciseName: exercise.name,
                setIndex: set.index,
                column: column,
                operation: operation,
                valueToWrite: valueToWrite,
                expectedCurrentValue: expectedCurrentValue
            )
        )
    }

    private func isFinalSet(_ set: ExerciseSet) -> Bool {
        let sets = set.exercise?.sets ?? []
        return set.index == (sets.map(\.index).max() ?? set.index)
    }

    private func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }
}
