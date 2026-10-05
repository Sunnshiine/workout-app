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
    /// Stored rather than computed so a read never walks the Block's Set states.
    /// `refreshCurrentSession()` resolves it at every write point that can move it.
    private(set) var currentSession: Session?
    /// Answered in `view(_:)` rather than derived in `reload()`, because a sync can land a log
    /// that moves the Current Session under an athlete who never navigated anywhere: they were
    /// at the live edge when they chose, so the reload has to carry them forward with it.
    ///
    /// An address rather than the Session itself, captured while that Session is still live: a
    /// sync deletes the whole Block and inserts the re-parsed one, and the deleted Session no
    /// longer reliably knows its own Week.
    private var browsedTo: SessionAddress?
    private var currentSessionOverrideRevision = 0

    private let context: ModelContext
    private let tracker = SessionProgressTracker()
    private let defaults: AppDefaults
    private let lastPerformed: any LastPerformedIndexing
    private let now: @MainActor () -> Date

    init(
        context: ModelContext,
        defaults: AppDefaults,
        lastPerformed: any LastPerformedIndexing = NoopLastPerformedIndex(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.context = context
        self.defaults = defaults
        self.lastPerformed = lastPerformed
        self.now = now
    }

    var canMoveOn: Bool {
        guard let block, let currentSession else { return false }
        return tracker.moveOnDestination(from: currentSession, in: block).isOffered
    }

    var liveEdge: LiveEdge { LiveEdge.resolve(viewedSession: viewedSession, currentSession: currentSession) }
    var isViewingLiveEdge: Bool { liveEdge.isAtLiveEdge }
    var openExercises: [Exercise] {
        guard let currentSession else { return [] }
        return tracker.openExercises(for: currentSession).map(\.exercise)
    }

    var currentSessionDebugInfo: CurrentSessionDebugInfo {
        _ = currentSessionOverrideRevision
        guard let block else {
            return CurrentSessionDebugInfo(
                currentBlockTab: "None",
                sheetDerivedSession: "None",
                manualOverrideSession: "None",
                viewedSession: sessionLabel(for: viewedSession),
                resolvedCurrentSession: "None",
                reason: "No Block is loaded, so no Current Session is resolved.",
                localOnlyNote: nil
            )
        }

        let override = currentSessionOverride(in: block)
        let overrideSession = override.flatMap { tracker.session(for: $0, in: block) }
        let sheetDerivedSession = tracker.currentSession(in: block)
        let resolvedSession = tracker.currentSession(in: block, override: override)
        let isManualOverrideActive = overrideSession?.persistentModelID == resolvedSession?.persistentModelID

        return CurrentSessionDebugInfo(
            currentBlockTab: block.tabName,
            sheetDerivedSession: sessionLabel(for: sheetDerivedSession),
            manualOverrideSession: manualOverrideLabel(hasOverride: override != nil, session: overrideSession),
            viewedSession: sessionLabel(for: viewedSession),
            resolvedCurrentSession: sessionLabel(for: resolvedSession),
            reason: resolutionReason(
                hasOverride: override != nil,
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
        return currentSessionOverride(in: block) != nil
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
        persistCurrentSessionOverride(tracker.persistedIdentity(of: viewedSession), in: block)
        view(viewedSession)
    }

    func resetCurrentSessionOverride() {
        guard let block else { return }
        defaults.removeValue(forKey: tracker.currentSessionOverrideStorageKey(forBlockTab: block.tabName))
        currentSessionOverrideRevision += 1
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
            persistCurrentSessionOverride(tracker.persistedIdentity(of: nextSession), in: block)
            view(nextSession)
        }
    }

    // MARK: - Private Helpers

    private func refreshCurrentSession() {
        let resolved = block.flatMap { tracker.currentSession(in: $0, override: currentSessionOverride(in: $0)) }
        if resolved !== currentSession { currentSession = resolved }
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

    /// The persisted manual Current-Session override for `block`, resolved through the
    /// navigation module's opaque identity token so the store never reasons about the
    /// order encoding or its versioning.
    private func currentSessionOverride(in block: Block) -> PersistedSessionIdentity? {
        let key = tracker.currentSessionOverrideStorageKey(forBlockTab: block.tabName)
        return defaults.integer(forKey: key).map(PersistedSessionIdentity.init(storageValue:))
    }

    private func persistCurrentSessionOverride(_ identity: PersistedSessionIdentity, in block: Block) {
        defaults.set(identity.storageValue, forKey: tracker.currentSessionOverrideStorageKey(forBlockTab: block.tabName))
        currentSessionOverrideRevision += 1
        refreshCurrentSession()
    }

    private func sessionLabel(for session: Session?) -> String {
        guard let address = session?.address else { return "None" }
        return "Week \(address.week), Day \(address.day)"
    }

    private func manualOverrideLabel(hasOverride: Bool, session: Session?) -> String {
        guard hasOverride else { return "None" }
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
        try writeNotes(of: set, operation: .upsert, valueToWrite: log.formatted) { set.markLogged(log, at: now()) }
    }

    func skip(_ set: ExerciseSet) throws {
        try writeNotes(of: set, operation: .upsert, valueToWrite: SetLogToken.skipSentinel) { set.markSkipped() }
    }

    func deleteLog(for set: ExerciseSet) throws {
        try writeNotes(of: set, operation: .delete, valueToWrite: nil) { set.markPending() }
    }

    /// The one Set-state writer. The refresh is deferred because `transition` moves the Set in
    /// memory before any step that can throw, and nothing rolls it back.
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
