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
    /// Written only by `view(_:)`, which keeps `browsedTo` in step with it.
    private(set) var viewedSession: Session?
    private(set) var moveOnCelebrationSession: Session?
    private(set) var moveOnCelebrationRequestedAt: Date?
    private(set) var pendingBlockOverviewRequest: BlockOverviewNavigationRequest?
    private(set) var currentSession: Session?
    /// Answered in `view(_:)` rather than derived in `reload()`, because a sync can land a log
    /// that moves the Current Session under an athlete who never navigated anywhere: they were
    /// at the live edge when they chose, so the reload has to carry them forward with it.
    ///
    /// An address rather than the Session itself, captured while that Session is still live: a
    /// sync deletes the whole Block and inserts the re-parsed one, and the deleted Session no
    /// longer reliably knows its own Week.
    private var browsedTo: SessionAddress?

    private let context: ModelContext
    private let tracker = SessionProgressTracker()
    private let pin: CurrentSessionPin
    private let lastPerformed: any LastPerformedIndexing
    private let now: @MainActor () -> Date

    init(
        context: ModelContext,
        defaults: AppDefaults,
        lastPerformed: any LastPerformedIndexing = NoopLastPerformedIndex(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.context = context
        self.pin = CurrentSessionPin(defaults: defaults)
        self.lastPerformed = lastPerformed
        self.now = now
    }

    var canMoveOn: Bool {
        guard let block, let currentSession else { return false }
        return tracker.moveOnDestination(from: currentSession, in: block).isOffered
    }

    var liveEdge: LiveEdge { LiveEdge.resolve(viewedSession: viewedSession, currentSession: currentSession) }

    func liveEdge(for session: Session) -> LiveEdge {
        LiveEdge.resolve(viewedSession: session, currentSession: currentSession)
    }

    var isViewingLiveEdge: Bool { liveEdge.isAtLiveEdge }
    var openExercises: [Exercise] {
        guard let currentSession else { return [] }
        return tracker.openExercises(for: currentSession).map(\.exercise)
    }

    /// Nil while no Block is loaded.
    var currentSessionResolution: CurrentSessionResolution? { block.map(pin.resolve(in:)) }

    var currentSessionDebugInfo: CurrentSessionDebugInfo {
        CurrentSessionDebugInfo(resolution: currentSessionResolution, viewedSession: viewedSession)
    }

    func reload() {
        block = try? context.fetch(FetchDescriptor<Block>()).first
        refreshCurrentSession()

        guard let browsed = browsedTo, let browsedSession = block?.session(at: browsed) else {
            view(currentSession)
            return
        }

        view(browsedSession)
    }

    func show(_ address: SessionAddress) {
        view(block?.session(at: address))
    }

    func showCurrent() {
        view(currentSession)
    }

    func makeViewedSessionCurrent() {
        guard let block, let viewedSession else { return }
        pinCurrentSession(viewedSession, in: block, by: .madeCurrent)
        view(viewedSession)
    }

    func clearCurrentSessionPin() {
        guard let block else { return }
        pin.clear(in: block)
        refreshCurrentSession()
        view(currentSession)
    }

    func requestBlockOverviewPresentation() { pendingBlockOverviewRequest = BlockOverviewNavigationRequest() }

    func clearBlockOverviewRequest() { pendingBlockOverviewRequest = nil }

    func requestMoveOnCelebration() {
        guard
            let block,
            let currentSession,
            tracker.moveOnDestination(from: currentSession, in: block).isOffered
        else { return }

        moveOnCelebrationSession = currentSession
        moveOnCelebrationRequestedAt = now()
        view(currentSession)
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

        switch tracker.moveOnDestination(from: session, in: block) {
        case .notOffered:
            return
        case .returnToBlockOverview:
            requestBlockOverviewPresentation()
        case .advance(to: let nextSession):
            pinCurrentSession(nextSession, in: block, by: .moveOn)
            view(nextSession)
        }
    }

    // MARK: - Private Helpers

    private func refreshCurrentSession() {
        currentSession = currentSessionResolution?.session
    }

    private func pinCurrentSession(_ session: Session, in block: Block, by author: CurrentSessionPin.Author) {
        pin.pin(session, in: block, by: author)
        refreshCurrentSession()
    }

    private func view(_ session: Session?) {
        viewedSession = session
        guard !isViewingLiveEdge, let address = session?.address else {
            browsedTo = nil
            return
        }
        browsedTo = address
    }

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
        let coordinates = try SetCoordinates(of: set)
        context.insert(
            PendingWrite(
                session: coordinates.session,
                dayNumbering: coordinates.dayNumbering,
                exerciseName: coordinates.exerciseName,
                setIndex: coordinates.setIndex,
                column: column,
                operation: operation,
                valueToWrite: valueToWrite,
                expectedCurrentValue: expectedCurrentValue
            )
        )
    }

    private func refreshLastPerformed(for set: ExerciseSet) throws {
        let coordinates = try SetCoordinates(of: set)
        guard let resultText = set.exercise?.setLevelCompletionEvidence.resultText else {
            try lastPerformed.retract(fullName: coordinates.exerciseName, source: coordinates.session.storageValue)
            return
        }
        try lastPerformed.ingest([
            LastPerformedEntry(
                fullName: coordinates.exerciseName,
                baseName: coordinates.exerciseBaseName,
                resultText: resultText,
                performedOn: coordinates.sessionDate ?? Date(),
                source: coordinates.session.storageValue
            )
        ])
    }

    private func enqueueLastSetRPEMirror(for set: ExerciseSet, replacing previous: RPE?) throws {
        guard let mirror = LastSetRPEMirror(after: set, replacing: previous) else { return }
        try enqueue(
            for: set,
            column: LastSetRPEMirror.column,
            operation: mirror.operation,
            valueToWrite: mirror.valueToWrite,
            expectedCurrentValue: mirror.expectedCurrentValue
        )
    }
}

extension WorkoutStore {
    func log(_ set: ExerciseSet, as log: SetLog) throws {
        try writeNotes(of: set, operation: .upsert, valueToWrite: log.formatted) { set.markLogged(log, at: now()) }
    }

    func skip(_ set: ExerciseSet) throws {
        try writeNotes(of: set, operation: .upsert, valueToWrite: SetLogToken.skipSentinel) { set.markSkipped() }
    }

    func deleteLog(for set: ExerciseSet) throws {
        try writeNotes(of: set, operation: .delete, valueToWrite: nil) { set.markPending() }
    }

    private func writeNotes(
        of set: ExerciseSet,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        transition: () -> Void
    ) throws {
        defer { refreshCurrentSession() }
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog?.rpe
        transition()
        try enqueue(
            for: set,
            column: .notes,
            operation: operation,
            valueToWrite: valueToWrite,
            expectedCurrentValue: previousValue
        )
        try enqueueLastSetRPEMirror(for: set, replacing: previousRPE)
        try refreshLastPerformed(for: set)
        try context.save()
    }
}
