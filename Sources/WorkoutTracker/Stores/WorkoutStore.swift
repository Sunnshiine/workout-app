import Foundation
import SwiftData

enum WorkoutLoggingError: Error, Equatable {
    case missingExercise
    case missingSession
    /// The sync that replaced its Block took the Session out of it, so the Set has no place in the
    /// Sheet to write to.
    case detachedSession
}

struct BlockOverviewNavigationRequest: Equatable, Identifiable {
    let id = UUID()
}

@MainActor
@Observable
final class WorkoutStore {
    // The reload root: reload() fetches it again, and every other Session the store hands out
    // resolves through it.
    private(set) var block: Block?
    private(set) var pendingBlockOverviewRequest: BlockOverviewNavigationRequest?
    // Stored rather than resolved on each read, so its observers hear it only when it moves
    // (observersHearTheCurrentSessionOnlyWhenItMoves). Every write to `block` refreshes it.
    private(set) var currentSession: Session?
    private var viewing = Viewing.currentSession
    private var moveOnCelebration: MoveOnCelebration?

    /// By address, because a sync deletes the whole Block and inserts the re-parsed one. The
    /// Current Session is followed wherever a write or a sync moves it, and a browsed Session is
    /// found again in each Block.
    private enum Viewing: Equatable {
        case currentSession
        case browsed(SessionAddress)
        /// An address the Block did not hold: no Viewed Session until the next reload returns to
        /// the Current Session.
        case nothing
    }

    /// By address, so a Move On from a celebration a sync landed under advances from the
    /// re-parsed Session.
    private struct MoveOnCelebration: Equatable {
        let address: SessionAddress
        let requestedAt: Date
    }

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

    var viewedSession: Session? {
        switch viewing {
        case .currentSession: currentSession
        case .browsed(let address): block?.session(at: address)
        case .nothing: nil
        }
    }

    var moveOnCelebrationSession: Session? { moveOnCelebration.flatMap { block?.session(at: $0.address) } }

    var moveOnCelebrationRequestedAt: Date? { moveOnCelebration?.requestedAt }

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
        // A sync that took the celebrated Session out of the Block ends the celebration, since
        // there is no longer a Session to Move On from.
        if moveOnCelebrationSession == nil { moveOnCelebration = nil }

        guard case .browsed(let address) = viewing, block?.session(at: address) != nil else {
            viewing = .currentSession
            return
        }
        show(address)
    }

    /// An address that holds the Current Session views it at the live edge, so a later write or
    /// sync that moves the Current Session carries the view along.
    func show(_ address: SessionAddress) {
        guard let session = block?.session(at: address) else {
            viewing = .nothing
            return
        }
        viewing = liveEdge(for: session).isAtLiveEdge ? .currentSession : .browsed(address)
    }

    func showCurrent() {
        viewing = .currentSession
    }

    func makeViewedSessionCurrent() {
        guard let block, let viewedSession else { return }
        pinCurrentSession(viewedSession, in: block, by: .madeCurrent)
        if case .browsed(let address) = viewing { show(address) }
    }

    func clearCurrentSessionPin() {
        guard let block else { return }
        pin.clear(in: block)
        refreshCurrentSession()
        viewing = .currentSession
    }

    func requestBlockOverviewPresentation() { pendingBlockOverviewRequest = BlockOverviewNavigationRequest() }

    func clearBlockOverviewRequest() { pendingBlockOverviewRequest = nil }

    func requestMoveOnCelebration() {
        guard
            let block,
            let currentSession,
            let address = currentSession.address,
            tracker.moveOnDestination(from: currentSession, in: block).isOffered
        else { return }

        moveOnCelebration = MoveOnCelebration(address: address, requestedAt: now())
        viewing = .currentSession
    }

    func dismissMoveOnCelebration() {
        guard let session = moveOnCelebrationSession else { return }
        moveOnCelebration = nil
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
            if let address = nextSession.address { show(address) }
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
                exercise: coordinates.exercise,
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
            try lastPerformed.retract(fullName: coordinates.exercise.name.entered, source: coordinates.session.storageValue)
            return
        }
        try lastPerformed.ingest([
            LastPerformedEntry(
                exerciseName: coordinates.exercise.name,
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
        guard let block, block.holds(set) else { throw WorkoutLoggingError.detachedSession }
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
