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
    /// The Week and Day the athlete browsed to, or `nil` while they are following the live edge.
    ///
    /// Answered in `view(_:)` rather than derived in `reload()`, because a sync can land a log
    /// that moves the Current Session under an athlete who never navigated anywhere: they were
    /// at the live edge when they chose, so the reload has to carry them forward with it.
    ///
    /// An address rather than the Session itself, captured while that Session is still live: a
    /// sync deletes the whole Block and inserts the re-parsed one, and the deleted Session no
    /// longer reliably knows its own Week.
    private var browsedTo: (week: Int, day: Int)?
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
        return block.flatMap { tracker.currentSession(in: $0, override: currentSessionOverride(in: $0)) }
    }

    var canMoveOn: Bool {
        guard let block, let currentSession else { return false }
        return tracker.moveOnDestination(from: currentSession, in: block).isOffered
    }

    var liveEdge: LiveEdge { LiveEdge.resolve(viewedSession: displayedSession, currentSession: currentSession) }
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
                displayedSession: sessionLabel(for: displayedSession),
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
            displayedSession: sessionLabel(for: displayedSession),
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

    /// Re-reads the Block, then puts the athlete back where they belong: on the Session they
    /// browsed to if they chose one and it survived the re-parse, otherwise on the Current
    /// Session, which by then may have moved.
    func reload() {
        block = try? context.fetch(FetchDescriptor<Block>()).first

        guard let browsed = browsedTo, let browsedSession = session(inWeek: browsed.week, day: browsed.day) else {
            view(currentSession)
            return
        }

        view(browsedSession)
    }

    func show(week: Int, day: Int) {
        view(session(inWeek: week, day: day))
    }

    func showCurrent() {
        view(currentSession)
    }

    func makeDisplayedSessionCurrent() {
        guard let block, let displayedSession else { return }
        persistCurrentSessionOverride(tracker.persistedIdentity(of: displayedSession), in: block)
        view(displayedSession)
    }

    func resetCurrentSessionOverride() {
        guard let block else { return }
        defaults.removeObject(forKey: tracker.currentSessionOverrideStorageKey(forBlockTab: block.tabName))
        currentSessionOverrideRevision += 1
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

    /// The only writer of `displayedSession`. Every way the athlete can change what they are
    /// looking at goes through it, so `browsedTo` is answered once here instead of being
    /// restated at each navigation entry point.
    private func view(_ session: Session?) {
        displayedSession = session
        guard !isViewingLiveEdge, let session, let week = session.week else {
            browsedTo = nil
            return
        }
        browsedTo = (week: week.number, day: session.dayNumber)
    }

    private func session(inWeek week: Int, day: Int) -> Session? {
        block?.weeks.first { $0.number == week }?.sessions.first { $0.dayNumber == day }
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
                blockTab: coordinates.blockTab,
                week: coordinates.weekNumber,
                day: coordinates.dayNumber,
                exerciseName: coordinates.exerciseName,
                setIndex: coordinates.setIndex,
                column: column,
                operation: operation,
                valueToWrite: valueToWrite,
                expectedCurrentValue: expectedCurrentValue
            )
        )
    }

    private func updateLastPerformed(for set: ExerciseSet, log: SetLog) throws {
        let coordinates = try SetCoordinates(of: set)
        try lastPerformed.ingest([
            LastPerformedEntry(
                fullName: coordinates.exerciseName,
                baseName: coordinates.exerciseBaseName,
                result: log,
                performedOn: coordinates.sessionDate ?? Date(),
                source: SessionCoordinate(
                    blockTab: coordinates.blockTab,
                    weekNumber: coordinates.weekNumber,
                    dayNumber: coordinates.dayNumber
                ).storageValue
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
        guard defaults.object(forKey: key) != nil else { return nil }
        return PersistedSessionIdentity(storageValue: defaults.integer(forKey: key))
    }

    private func persistCurrentSessionOverride(_ identity: PersistedSessionIdentity, in block: Block) {
        defaults.set(identity.storageValue, forKey: tracker.currentSessionOverrideStorageKey(forBlockTab: block.tabName))
        currentSessionOverrideRevision += 1
    }

    private func sessionLabel(for session: Session?) -> String {
        guard let session, let week = session.week else { return "None" }
        return "Week \(week.number), Day \(session.dayNumber)"
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
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog?.rpe
        set.markLogged(log, at: now())
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: log.formatted,
            expectedCurrentValue: previousValue
        )
        try enqueueLastSetRPEMirror(for: set, replacing: previousRPE)
        try updateLastPerformed(for: set, log: log)
        try context.save()
    }

    func skip(_ set: ExerciseSet) throws {
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog?.rpe
        set.markSkipped()
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: SetLogToken.skipSentinel,
            expectedCurrentValue: previousValue
        )
        try enqueueLastSetRPEMirror(for: set, replacing: previousRPE)
        try context.save()
    }

    func deleteLog(for set: ExerciseSet) throws {
        let previousValue = notesValue(for: set)
        let previousRPE = set.setLog?.rpe
        set.markPending()
        try enqueue(
            for: set,
            column: .notes,
            operation: .delete,
            valueToWrite: nil,
            expectedCurrentValue: previousValue
        )
        try enqueueLastSetRPEMirror(for: set, replacing: previousRPE)
        try context.save()
    }
}
