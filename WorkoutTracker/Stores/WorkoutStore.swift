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
    private(set) var moveOnCelebrationRequestedAt: Date?
    private(set) var pendingBlockOverviewRequest: BlockOverviewNavigationRequest?
    private var shouldPreserveDisplayedSessionOnReload = false
    private var currentSessionOverrideRevision = 0

    private let context: ModelContext
    private let tracker = SessionProgressTracker()
    private let defaults: UserDefaults
    private let lastPerformed: any LastPerformedIndexing
    private let now: @MainActor () -> Date

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        lastPerformed: any LastPerformedIndexing = NoopLastPerformedIndex(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.context = context
        self.defaults = defaults
        self.lastPerformed = lastPerformed
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
        guard let currentSession else { return [] }
        return tracker.openExercises(inCurrentWeekOf: currentSession)
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
        moveOnCelebrationRequestedAt = now()
        displayedSession = currentSession
        shouldPreserveDisplayedSessionOnReload = false
    }

    func dismissMoveOnCelebration() {
        guard let session = moveOnCelebrationSession else { return }
        moveOnCelebrationSession = nil
        moveOnCelebrationRequestedAt = nil
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

    // MARK: - Private Helpers

    private func notesValue(for set: ExerciseSet) -> String {
        SetLogToken.serialize(
            SetLogToken.Classification(
                state: set.state,
                setLog: set.setLog,
                unstructuredSetLog: set.unstructuredSetLog
            )
        )
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

        try lastPerformed.ingest([
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

    private func currentSessionOverrideOrder(in block: Block) -> Int? {
        let key = currentSessionOverrideKey(for: block.tabName)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    private func currentSessionOverrideKey(for tabName: String) -> String {
        // V2: the Session order encoding changed stride (4 → 7) to support 2–6 day Weeks.
        // A new key orphans any legacy `advancedToOrder_*` value so it can never resolve to the
        // wrong Session under the new stride; the override simply resets to the derived Current
        // Session once, which the athlete can re-set with one tap.
        "advancedToOrderV2_\(tabName)"
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

extension WorkoutStore {
    func log(_ set: ExerciseSet, as log: SetLog) throws {
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        let wasLogged = set.state == .logged
        set.setLog = log
        set.unstructuredSetLog = nil
        set.state = .logged
        if !wasLogged {
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
        set.state = .skipped
        set.loggedAt = nil
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: SetLogToken.skipSentinel,
            expectedCurrentValue: previousValue
        )
        try context.save()
    }

    func deleteLog(for set: ExerciseSet) throws {
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = nil
        set.unstructuredSetLog = nil
        set.state = .pending
        set.loggedAt = nil
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
