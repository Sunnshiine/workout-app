import Foundation
import SwiftData

/// The one composition root: builds the model container and the four stores the app and the CLI
/// both run on. The stores stay internal; everything outside this module goes through the facade.
@MainActor
public final class WorkoutApplication {
    let container: ModelContainer
    let settings: SettingsStore
    let workout: WorkoutStore
    let sync: SyncCoordinator
    let lastPerformed: LastPerformedLookupStore
    let sheetsClient: any SheetsClient

    static let schema = Schema([
        Block.self, PendingWrite.self, WriteTargetAuditEntry.self, LastPerformedEntry.self, HistoryFillCursor.self
    ])

    public init(environment: AppEnvironment) throws {
        container = try ModelContainer(for: Self.schema, configurations: Self.configuration(for: environment.storage))
        let context = container.mainContext
        try environment.seed?(context)
        sheetsClient = environment.sheetsClient
        lastPerformed = LastPerformedLookupStore(context: context)
        settings = SettingsStore(
            defaults: environment.defaults,
            hasPriorAppState: environment.derivesPriorAppStateFromStore && Self.hasPriorAppState(in: context)
        )
        workout = WorkoutStore(
            context: context,
            defaults: environment.defaults,
            lastPerformed: lastPerformed,
            now: environment.now
        )
        sync = SyncCoordinator(client: environment.sheetsClient, context: context, lastPerformed: lastPerformed)
        workout.reload()
    }

    private static func configuration(for storage: AppEnvironment.Storage) -> ModelConfiguration {
        switch storage {
        case .inMemory:
            // A unique name keeps two in-memory applications in one process from sharing a store.
            ModelConfiguration("WorkoutApplication.\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        case .deviceDefault:
            ModelConfiguration(schema: schema)
        case .file(let url):
            ModelConfiguration(schema: schema, url: url)
        }
    }

    private static func hasPriorAppState(in context: ModelContext) -> Bool {
        ((try? context.fetch(FetchDescriptor<Block>()).isEmpty) == false)
    }
}

extension WorkoutApplication {
    /// The onboarding path: `SettingsSheetSwitchStore.requestSwitch`, which syncs, commits the
    /// selection, and reloads the store.
    public func selectSpreadsheet(id: String, title: String?) async throws -> AppSnapshot {
        let switcher = SettingsSheetSwitchStore(settings: settings, sync: sync) { [workout] in workout.reload() }
        switch await switcher.requestSwitch(to: SheetSelection(spreadsheetId: id, title: title)) {
        case .switched, .unchanged:
            return try snapshot()
        case .requiresConfirmation:
            throw ApplicationError.sheetSwitchRequiresDiscard
        case .failed:
            throw ApplicationError.sheetSwitchFailed(switcher.errorMessage ?? "unknown")
        }
    }

    public func snapshot() throws -> AppSnapshot {
        let current = workout.currentSession
        return AppSnapshot(
            spreadsheetId: settings.spreadsheetId,
            spreadsheetTitle: settings.spreadsheetTitle,
            syncState: SyncStateSnapshot(sync.state),
            pendingWriteCount: try queuedWrites().count,
            block: workout.block.map(BlockSummary.init),
            currentSession: current.flatMap(address(of:)),
            currentSessionReason: workout.currentSessionDebugInfo.reason,
            currentSessionIsOverridden: workout.hasCurrentSessionOverride,
            displayedSession: workout.displayedSession.flatMap(address(of:)),
            canMoveOn: workout.canMoveOn,
            openExercises: workout.openExercises.compactMap(address(of:)),
            sessions: orderedSessions().map { session in
                SessionSummary(session.model, id: session.id, isCurrent: session.model === current)
            }
        )
    }

    /// `nil` is the Current Session.
    public func session(_ address: SessionAddress?) throws -> SessionSnapshot {
        let session = try address.map(resolveSession) ?? resolveCurrentSession()
        return SessionSnapshot(session.model, id: session.id, isCurrent: session.model === workout.currentSession)
    }

    /// `WorkoutStore.log(_:as:)`: the same call the Session stage makes.
    public func log(_ address: SetAddress, setLog: String) throws -> LogReport {
        guard let parsed = SetLog(formatted: setLog) else { throw ApplicationError.invalidSetLog(setLog) }
        let set = try resolveSet(address)
        try workout.log(set, as: parsed)
        return LogReport(
            set: SetSnapshot(set, id: address),
            pendingWriteCount: try queuedWrites().count,
            exerciseIsComplete: set.exercise?.isComplete ?? false
        )
    }

    /// `SyncCoordinator.flushPending(spreadsheetId:)`: what the stage requests after every log.
    public func flush() async throws -> FlushReport {
        let spreadsheetId = try configuredSpreadsheetId()
        let before = try queuedWrites()
        // Counted before the flush: the records are live model objects the flush mutates in place.
        let attempted = before.filter { $0.status == .pending }.count
        await sync.flushPending(spreadsheetId: spreadsheetId)
        let after = try queuedWrites()
        // A flushed write is deleted from the queue; a conflicted one stays with its status changed.
        return FlushReport(
            attempted: attempted,
            written: before.count - after.count,
            conflictedWrites: conflictMessages(in: after),
            remainingPendingWrites: after.count,
            syncState: SyncStateSnapshot(sync.state)
        )
    }

    /// `SyncCoordinator.sync(spreadsheetId:)` followed by the reload every `onSynced` performs.
    public func sync() async throws -> SyncReport {
        let spreadsheetId = try configuredSpreadsheetId()
        let didSync = await sync.sync(spreadsheetId: spreadsheetId)
        workout.reload()
        let state = SyncStateSnapshot(sync.state)
        guard didSync else { throw ApplicationError.syncFailed(state) }
        let queued = try queuedWrites()
        return SyncReport(
            syncState: state,
            block: workout.block.map(BlockSummary.init),
            currentSession: workout.currentSession.flatMap(address(of:)),
            pendingWriteCount: queued.count,
            conflictedWrites: conflictMessages(in: queued)
        )
    }

    /// Reads a tab straight through the SheetsClient; `nil` is the cached Block's tab, or the
    /// Sheet's current Block tab when nothing is cached yet.
    public func sheet(tab: String?) async throws -> SheetTabSnapshot {
        let spreadsheetId = try configuredSpreadsheetId()
        let titles = try await sheetsClient.listTabTitles(spreadsheetId: spreadsheetId)
        let resolved: String
        if let tab {
            guard titles.contains(tab) else { throw ApplicationError.unknownTab(name: tab, candidates: titles) }
            resolved = tab
        } else {
            guard let blockTab = workout.block?.tabName ?? currentBlockTab(from: titles) else {
                throw ApplicationError.noBlock
            }
            resolved = blockTab
        }
        let snapshot = try await sheetsClient.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: resolved)
        return SheetTabSnapshot(tab: resolved, snapshot: snapshot)
    }
}

extension WorkoutApplication {
    fileprivate struct AddressedSession {
        let id: SessionAddress
        let model: Session
    }

    fileprivate func configuredSpreadsheetId() throws -> String {
        guard let spreadsheetId = settings.spreadsheetId else { throw ApplicationError.notConfigured }
        return spreadsheetId
    }

    /// Every queued record, conflicts included: what the app's `pendingWrites` state counts.
    fileprivate func queuedWrites() throws -> [PendingWrite] {
        try sync.fetchPendingWriteRecords()
    }

    fileprivate func conflictMessages(in writes: [PendingWrite]) -> [String] {
        writes.filter { $0.status == .conflict }.map { "\($0.exerciseName): \($0.lastError ?? "conflict")" }
    }

    fileprivate func orderedSessions() -> [AddressedSession] {
        guard let block = workout.block else { return [] }
        return block.weeks
            .sorted { $0.number < $1.number }
            .flatMap { week in
                week.sessions
                    .sorted { $0.dayNumber < $1.dayNumber }
                    .map { AddressedSession(id: SessionAddress(week: week.number, day: $0.dayNumber), model: $0) }
            }
    }

    fileprivate func address(of session: Session) -> SessionAddress? {
        session.week.map { SessionAddress(week: $0.number, day: session.dayNumber) }
    }

    fileprivate func address(of exercise: Exercise) -> ExerciseAddress? {
        exercise.session.flatMap(address(of:)).map { ExerciseAddress(session: $0, order: exercise.order) }
    }

    fileprivate func resolveCurrentSession() throws -> AddressedSession {
        guard workout.block != nil else { throw ApplicationError.noBlock }
        guard let current = workout.currentSession, let id = address(of: current) else {
            throw ApplicationError.unknownSession(address: "current", candidates: orderedSessions().map(\.id.description))
        }
        return AddressedSession(id: id, model: current)
    }

    fileprivate func resolveSession(_ address: SessionAddress) throws -> AddressedSession {
        guard workout.block != nil else { throw ApplicationError.noBlock }
        let sessions = orderedSessions()
        guard let session = sessions.first(where: { $0.id == address }) else {
            throw ApplicationError.unknownSession(address: address.description, candidates: sessions.map(\.id.description))
        }
        return session
    }

    fileprivate func resolveExercise(_ address: ExerciseAddress) throws -> Exercise {
        let session = try resolveSession(address.session).model
        guard !session.exercises.isEmpty else { throw ApplicationError.sessionUnavailable(address.session.description) }
        guard let exercise = session.exercises.first(where: { $0.order == address.order }) else {
            throw ApplicationError.unknownExercise(
                address: address.description,
                candidates: session.exercises.map(\.order).sorted().map { ExerciseAddress(session: address.session, order: $0).description }
            )
        }
        return exercise
    }

    fileprivate func resolveSet(_ address: SetAddress) throws -> ExerciseSet {
        let exercise = try resolveExercise(address.exercise)
        guard let set = exercise.sets.first(where: { $0.index == address.index }) else {
            throw ApplicationError.unknownSet(
                address: address.description,
                candidates: exercise.sets.map(\.index).sorted().map { SetAddress(exercise: address.exercise, index: $0).description }
            )
        }
        return set
    }
}
