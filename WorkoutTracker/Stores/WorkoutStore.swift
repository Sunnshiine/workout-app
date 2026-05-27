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
    private var shouldPreserveDisplayedSessionOnReload = false

    private let context: ModelContext
    private let tracker = SessionProgressTracker()
    private let defaults: UserDefaults

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    var currentSession: Session? {
        block.flatMap { tracker.currentSession(in: $0, advancedToOrder: advancedToOrder(in: $0)) }
    }

    var canMoveOn: Bool {
        guard let block, let currentSession else { return false }
        return tracker.nextSession(after: currentSession, in: block) != nil
    }

    var isViewingLiveEdge: Bool { displayedSession?.persistentModelID == currentSession?.persistentModelID }
    var openExercises: [Exercise] {
        guard let block, let currentSession else { return [] }
        return tracker.openExercises(in: block, currentSession: currentSession)
    }

    func reload() {
        let displayedWeek = displayedSession?.week?.number
        let displayedDay = displayedSession?.dayNumber
        block = try? context.fetch(FetchDescriptor<Block>()).first

        let preservedSession: Session?
        if shouldPreserveDisplayedSessionOnReload, let displayedWeek, let displayedDay {
            preservedSession = block?.weeks.first(where: { $0.number == displayedWeek })?
                .sessions.first(where: { $0.dayNumber == displayedDay })
        } else {
            preservedSession = nil
        }

        if let displayedSession = preservedSession {
            self.displayedSession = displayedSession
            shouldPreserveDisplayedSessionOnReload = !isViewingLiveEdge
            return
        }

        displayedSession = currentSession
        shouldPreserveDisplayedSessionOnReload = false
    }

    func show(week: Int, day: Int) {
        displayedSession = block?.weeks.first { $0.number == week }?.sessions.first { $0.dayNumber == day }
        shouldPreserveDisplayedSessionOnReload = !isViewingLiveEdge
    }

    func showCurrent() {
        displayedSession = currentSession
        shouldPreserveDisplayedSessionOnReload = false
    }

    func moveOn() {
        guard
            let block,
            let currentSession,
            let nextSession = tracker.nextSession(after: currentSession, in: block)
        else { return }

        defaults.set(tracker.order(of: nextSession), forKey: advanceKey(for: block.tabName))
        displayedSession = nextSession
        shouldPreserveDisplayedSessionOnReload = false
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
        try updateLastPerformed(for: set, log: log)
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

    private func updateLastPerformed(for set: ExerciseSet, log: SetLog) throws {
        guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
        guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
        guard let week = session.week else { throw WorkoutLoggingError.missingWeek }
        guard let block = week.block else { throw WorkoutLoggingError.missingBlock }

        try LastPerformedIndex(context: context).ingest([
            LastPerformedEntry(
                fullName: exercise.name,
                baseName: exercise.baseName,
                result: log,
                performedOn: session.date ?? Date(),
                source: "\(block.tabName) · W\(week.number) D\(session.dayNumber)"
            )
        ])
    }

    private func isFinalSet(_ set: ExerciseSet) -> Bool {
        let sets = set.exercise?.sets ?? []
        return set.index == (sets.map(\.index).max() ?? set.index)
    }

    private func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }

    private func advancedToOrder(in block: Block) -> Int? {
        let key = advanceKey(for: block.tabName)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    private func advanceKey(for tabName: String) -> String {
        "advancedToOrder_\(tabName)"
    }
}
