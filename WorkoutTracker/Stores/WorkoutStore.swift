import Foundation
import SwiftData

enum WorkoutLoggingError: Error, Equatable {
    case missingExercise
    case missingSession
    case missingWeek
    case missingBlock
}

struct BlockOverviewNavigationRequest: Equatable, Identifiable {
    let id = UUID()
}

@MainActor
@Observable
final class WorkoutStore {
    private(set) var block: Block?
    private(set) var displayedSession: Session?
    private(set) var moveOnCelebrationSession: Session?
    private(set) var moveOnCelebrationTiming: MoveOnCelebrationTiming?
    private(set) var pendingBlockOverviewRequest: BlockOverviewNavigationRequest?
    private var shouldPreserveDisplayedSessionOnReload = false
    private var currentSessionOverrideRevision = 0

    private let context: ModelContext
    private let tracker = SessionProgressTracker()
    private let defaults: UserDefaults
    private let lastPerformedLookupRefresher: any LastPerformedLookupRefreshing
    private let now: () -> Date

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        lastPerformedLookupRefresher: any LastPerformedLookupRefreshing = NoopLastPerformedLookupRefresher(),
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.defaults = defaults
        self.lastPerformedLookupRefresher = lastPerformedLookupRefresher
        self.now = now
    }

    var currentSession: Session? {
        _ = currentSessionOverrideRevision
        return block.flatMap { tracker.currentSession(in: $0, overrideOrder: currentSessionOverrideOrder(in: $0)) }
    }

    var canMoveOn: Bool {
        guard let block, let currentSession else { return false }
        return tracker.hasSessionAhead(after: currentSession, in: block)
    }

    var isViewingLiveEdge: Bool { displayedSession?.persistentModelID == currentSession?.persistentModelID }
    var openExercises: [Exercise] {
        guard let block, let currentSession else { return [] }
        return tracker.openExercises(in: block, currentSession: currentSession)
    }

    var currentSessionDebugInfo: CurrentSessionDebugInfo {
        _ = currentSessionOverrideRevision
        guard let block else {
            return CurrentSessionDebugInfo(
                currentBlockTab: "None",
                sheetDerivedSession: "None",
                manualOverrideSession: "None",
                displayedSession: sessionLabel(for: displayedSession),
                resolvedCurrentSession: "None",
                reason: "No Block is loaded, so no Current Session is resolved.",
                localOnlyNote: nil
            )
        }

        let overrideOrder = currentSessionOverrideOrder(in: block)
        let overrideSession = overrideOrder.flatMap { tracker.session(at: $0, in: block) }
        let sheetDerivedSession = tracker.currentSession(in: block)
        let resolvedSession = tracker.currentSession(in: block, overrideOrder: overrideOrder)
        let isManualOverrideActive = overrideSession?.persistentModelID == resolvedSession?.persistentModelID

        return CurrentSessionDebugInfo(
            currentBlockTab: block.tabName,
            sheetDerivedSession: sessionLabel(for: sheetDerivedSession),
            manualOverrideSession: manualOverrideLabel(order: overrideOrder, session: overrideSession),
            displayedSession: sessionLabel(for: displayedSession),
            resolvedCurrentSession: sessionLabel(for: resolvedSession),
            reason: resolutionReason(
                hasOverride: overrideOrder != nil,
                isManualOverrideActive: isManualOverrideActive,
                hasSheetDerivedSession: sheetDerivedSession != nil
            ),
            localOnlyNote: isManualOverrideActive
                ? "Manual Current Session override is local-only and is not Sheet data."
                : nil
        )
    }

    var hasCurrentSessionOverride: Bool {
        guard let block else { return false }
        return currentSessionOverrideOrder(in: block) != nil
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

    func makeDisplayedSessionCurrent() {
        guard let block, let displayedSession else { return }
        defaults.set(tracker.order(of: displayedSession), forKey: currentSessionOverrideKey(for: block.tabName))
        currentSessionOverrideRevision += 1
        shouldPreserveDisplayedSessionOnReload = false
    }

    func resetCurrentSessionOverride() {
        guard let block else { return }
        defaults.removeObject(forKey: currentSessionOverrideKey(for: block.tabName))
        currentSessionOverrideRevision += 1
        displayedSession = tracker.currentSession(in: block)
        shouldPreserveDisplayedSessionOnReload = false
    }

    func requestBlockOverviewPresentation() { pendingBlockOverviewRequest = BlockOverviewNavigationRequest() }

    func clearBlockOverviewRequest() { pendingBlockOverviewRequest = nil }

    func requestMoveOnCelebration() {
        guard
            let block,
            let currentSession,
            tracker.hasSessionAhead(after: currentSession, in: block)
        else { return }

        moveOnCelebrationSession = currentSession
        moveOnCelebrationTiming = moveOnCelebrationTiming(for: currentSession, requestedAt: now())
        displayedSession = currentSession
        shouldPreserveDisplayedSessionOnReload = false
    }

    func dismissMoveOnCelebration() {
        guard let session = moveOnCelebrationSession else { return }
        moveOnCelebrationSession = nil
        moveOnCelebrationTiming = nil
        advance(after: session)
    }

    func moveOn() {
        guard let currentSession else { return }
        advance(after: currentSession)
    }

    private func advance(after session: Session) {
        guard let block else { return }

        guard tracker.hasSessionAhead(after: session, in: block) else { return }

        guard let nextSession = tracker.nextSession(after: session, in: block) else {
            requestBlockOverviewPresentation()
            return
        }

        defaults.set(tracker.order(of: nextSession), forKey: currentSessionOverrideKey(for: block.tabName))
        currentSessionOverrideRevision += 1
        displayedSession = nextSession
        shouldPreserveDisplayedSessionOnReload = false
    }

    // MARK: - Optimistic Logging

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        let wasPending = set.state == .pending
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = log
        set.unstructuredSetLog = nil
        set.state = .logged
        if wasPending {
            set.loggedAt = now()
        }
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
        let previousValue = notesValue(for: set)
        set.setLog = nil
        set.unstructuredSetLog = nil
        set.loggedAt = nil
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
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = nil
        set.unstructuredSetLog = nil
        set.loggedAt = nil
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

}

extension WorkoutStore {
    // MARK: - Private Helpers

    private func notesValue(for set: ExerciseSet) -> String {
        if let setLog = set.setLog {
            return setLog.formatted
        }
        if let unstructuredSetLog = set.unstructuredSetLog {
            return unstructuredSetLog
        }
        if set.state == .skipped {
            return "skip"
        }
        return ""
    }

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
        lastPerformedLookupRefresher.refresh()
    }

    private func isFinalSet(_ set: ExerciseSet) -> Bool {
        let sets = set.exercise?.sets ?? []
        return set.index == (sets.map(\.index).max() ?? set.index)
    }

    private func moveOnCelebrationTiming(for session: Session, requestedAt: Date) -> MoveOnCelebrationTiming? {
        let loggedSets = session.exercises
            .flatMap(\.sets)
            .filter { $0.state == .logged }
        guard !loggedSets.isEmpty, loggedSets.allSatisfy({ $0.loggedAt != nil }) else {
            return nil
        }

        let firstLoggedAt = loggedSets.compactMap(\.loggedAt).min()
        return firstLoggedAt.map {
            MoveOnCelebrationTiming(firstLoggedAt: $0, requestedAt: requestedAt)
        }
    }

    private func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }

    private func currentSessionOverrideOrder(in block: Block) -> Int? {
        let key = currentSessionOverrideKey(for: block.tabName)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    private func currentSessionOverrideKey(for tabName: String) -> String {
        "advancedToOrder_\(tabName)"
    }

    private func sessionLabel(for session: Session?) -> String {
        guard let session, let week = session.week else { return "None" }
        return "Week \(week.number), Day \(session.dayNumber)"
    }

    private func manualOverrideLabel(order: Int?, session: Session?) -> String {
        guard order != nil else { return "None" }
        guard let session else { return "Saved override no longer matches this Block" }
        return sessionLabel(for: session)
    }

    private func resolutionReason(
        hasOverride: Bool,
        isManualOverrideActive: Bool,
        hasSheetDerivedSession: Bool
    ) -> String {
        if isManualOverrideActive {
            return "Manual override is active for this Block."
        }

        if hasOverride {
            return "Saved manual override no longer matches this Block, so Sheet-derived progress wins."
        }

        if hasSheetDerivedSession {
            return "No manual override is active, so Sheet-derived progress wins."
        }

        return "No Sheet-derived Session is available for this Block."
    }
}
