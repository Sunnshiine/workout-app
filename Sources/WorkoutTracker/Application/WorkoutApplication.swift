import AVFoundation
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
    let historyFill: ExerciseHistoryFill
    let connection: SheetConnection
    let sheetsClient: any SheetsClient
    /// Every press's Dictation Record, whichever surface pressed.
    let dictationJournal: DictationJournal

    static let schema = Schema([
        Block.self, PendingWrite.self, WriteTargetAuditEntry.self, LastPerformedEntry.self, HistoryFillCursor.self
    ])

    public init(environment: AppEnvironment) throws {
        container = try ModelContainer(for: Self.schema, configurations: Self.configuration(for: environment.storage))
        let context = container.mainContext
        try environment.seed?(context)
        sheetsClient = environment.sheetsClient
        dictationJournal = DictationJournal(storage: environment.dictationRecords)
        lastPerformed = LastPerformedLookupStore(context: context)
        settings = SettingsStore(
            defaults: environment.defaults,
            hasPriorAppState: Self.hasPriorAppState(in: context)
        )
        workout = WorkoutStore(
            context: context,
            defaults: environment.defaults,
            lastPerformed: lastPerformed,
            now: environment.now
        )
        historyFill = ExerciseHistoryFill(client: environment.sheetsClient, context: context, index: lastPerformed)
        sync = SyncCoordinator(
            client: environment.sheetsClient,
            context: context,
            lastPerformed: lastPerformed,
            historyFill: historyFill
        )
        connection = SheetConnection(settings: settings, sync: sync) { [workout] in workout.reload() }
        workout.reload()
    }

    private static func configuration(for storage: AppEnvironment.Storage) -> ModelConfiguration {
        switch storage {
        case .inMemory:
            ModelConfiguration("WorkoutApplication.\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        case .deviceDefault:
            ModelConfiguration(schema: schema)
        case .file(let url):
            ModelConfiguration(schema: schema, url: url)
        }
    }

    private static func hasPriorAppState(in context: ModelContext) -> Bool {
        guard let blocks = try? context.fetch(FetchDescriptor<Block>()) else { return false }
        return !blocks.isEmpty
    }
}

extension WorkoutApplication {
    public func selectSpreadsheet(id: String, title: String?) async throws -> AppSnapshot {
        switch await connection.requestSwitch(to: SheetSelection(spreadsheetId: id, title: title)) {
        case .switched, .unchanged:
            return try snapshot()
        case .requiresConfirmation:
            throw ApplicationError.sheetSwitchRequiresDiscard
        case .failed(let failure):
            throw ApplicationError.sheetSwitchFailed(failure.message)
        }
    }

    public func snapshot() throws -> AppSnapshot {
        let current = workout.currentSession
        return AppSnapshot(
            spreadsheetId: settings.spreadsheetId,
            spreadsheetTitle: settings.spreadsheetTitle,
            syncOutcome: SyncOutcomeSnapshot(sync.outcome),
            pendingWriteCount: try queuedWrites().count,
            block: workout.block.map(BlockSummary.init),
            currentSession: current.flatMap(\.address),
            currentSessionReason: workout.currentSessionDebugInfo.reason,
            currentSessionIsOverridden: workout.hasCurrentSessionOverride,
            viewedSession: workout.viewedSession.flatMap(\.address),
            canMoveOn: workout.canMoveOn,
            openExercises: workout.openExercises.compactMap(address(of:)),
            sessions: orderedSessions().map { session in
                SessionSummary(session.model, id: session.id, isCurrent: session.model === current)
            }
        )
    }

    /// `WorkoutStore.show(_:)`, or `showCurrent()` when the address is `nil`.
    @discardableResult
    public func view(_ address: SessionAddress?) throws -> AppSnapshot {
        if let address {
            _ = try resolveSession(address)
            workout.show(address)
        } else {
            workout.showCurrent()
        }
        return try snapshot()
    }

    /// `nil` is the Current Session.
    public func session(_ address: SessionAddress?) throws -> SessionSnapshot {
        let session = try address.map(resolveSession) ?? resolveCurrentSession()
        return SessionSnapshot(
            session.model,
            id: session.id,
            isCurrent: session.model === workout.currentSession,
            history: lastPerformed.snapshot
        )
    }

    /// `WorkoutStore.log(_:as:)`: the same call the Session stage makes.
    public func log(_ address: SetAddress, setLog: String) throws -> LogReport {
        guard let parsed = SetLog(formatted: setLog) else { throw ApplicationError.invalidSetLog(setLog) }
        let set = try resolveSet(address)
        try workout.log(set, as: parsed)
        return try report(on: set, at: address)
    }

    /// `WorkoutStore.skip(_:)`: the same call the Session stage makes.
    public func skip(_ address: SetAddress) throws -> LogReport {
        let set = try resolveSet(address)
        try workout.skip(set)
        return try report(on: set, at: address)
    }

    /// A Spoken Set read over what the Set's card pre-fills, then `log` or `skip` through the same
    /// store calls. One still missing a value, or rejected, writes nothing and reports why.
    public func say(_ transcript: String, at address: SetAddress) throws -> SayReport {
        try dictate([transcript], at: address)
    }

    /// `say` over a recognizer's transcripts, most likely first, under the Dictation write policy:
    /// only the most likely transcript writes, and a Set it does not read that the others agree
    /// on is reported `ambiguous` with nothing written. Every Dictation that writes without the
    /// card, headless or from a recording, ends here.
    public func dictate(_ candidates: [String], at address: SetAddress) throws -> SayReport {
        let set = try resolveSet(address)
        let context = SpokenSetContext(for: set, history: lastPerformed.snapshot)
        let outcome = SetDictation.decision(of: Hearing(live: .transcripts(candidates), recording: nil), in: context).outcome
        try write(outcome, to: set)
        return SayReport(outcome, report: try report(on: set, at: address))
    }

    /// `dictate` over a recording, heard by the speech model the mic listens with, configured the
    /// same way and read into transcripts the same way. `installing` receives the fraction of the
    /// model's assets installed, when the machine has yet to download them.
    @available(iOS 26, macOS 26, *)
    public func hear(
        _ recording: URL,
        at address: SetAddress,
        installing: @escaping @Sendable (Double) -> Void
    ) async throws -> HearReport {
        _ = try resolveSet(address)
        guard let file = try? AVAudioFile(forReading: recording) else { throw ApplicationError.unreadableRecording(recording.path) }
        let candidates: [String]
        do {
            candidates = try await SpeechListening.transcripts(of: file, installing: installing)
        } catch {
            throw ApplicationError.notHeard(error, in: recording.path)
        }
        return HearReport(candidates: candidates, report: try dictate(candidates, at: address))
    }

    /// The one place a Dictation's outcome reaches the store: `logged` and `skipped` write, the
    /// rest leave the Set as it was.
    func write(_ outcome: SetDictation.Outcome, to set: ExerciseSet) throws {
        switch outcome {
        case .logged(let setLog, _): try workout.log(set, as: setLog)
        case .skipped: try workout.skip(set)
        case .filled, .rejected: break
        }
    }

    /// `SyncCoordinator.flushPending(spreadsheetId:)`: what the stage requests after every log.
    public func flush() async throws -> FlushReport {
        let spreadsheetId = try configuredSpreadsheetId()
        let before = try queuedWrites()
        let attempted = before.filter { $0.status == .pending }.count
        await sync.flushPending(spreadsheetId: spreadsheetId)
        let after = try queuedWrites()
        return FlushReport(
            attempted: attempted,
            written: before.count - after.count,
            conflictedWrites: conflictMessages(in: after),
            remainingPendingWrites: after.count,
            syncOutcome: SyncOutcomeSnapshot(sync.outcome)
        )
    }

    public func sync() async throws -> SyncReport {
        switch await connection.syncNow() {
        case .synced: break
        case .noSheet: throw ApplicationError.notConfigured
        case .syncInProgress, .failed: throw ApplicationError.syncFailed(SyncOutcomeSnapshot(sync.outcome).status)
        }
        let outcome = SyncOutcomeSnapshot(sync.outcome)
        let queued = try queuedWrites()
        return SyncReport(
            syncOutcome: outcome,
            block: workout.block.map(BlockSummary.init),
            currentSession: workout.currentSession.flatMap(\.address),
            viewedSession: workout.viewedSession.flatMap(\.address),
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
            guard titles.contains(tab) else { throw ApplicationError.notFound(.tab, name: tab, candidates: titles) }
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

    /// What the Dictation Records in `records`, a journal file or a directory of them, add up to.
    /// It reads the records alone, so a journal copied off a phone needs no application.
    public static func dictationSummary(reading records: URL) throws -> DictationSummary {
        let lines = try DictationRecordLines(at: records)
        return DictationSummary(lines.records, unreadableLines: lines.unreadable)
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

    fileprivate func report(on set: ExerciseSet, at address: SetAddress) throws -> LogReport {
        LogReport(
            set: SetSnapshot(set, id: address, history: lastPerformed.snapshot),
            pendingWriteCount: try queuedWrites().count,
            exerciseIsComplete: set.exercise?.isComplete ?? false
        )
    }

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
                    .map { AddressedSession(id: week.address(of: $0), model: $0) }
            }
    }

    fileprivate func address(of exercise: Exercise) -> ExerciseAddress? {
        exercise.session?.address.map { ExerciseAddress(session: $0, order: exercise.order) }
    }

    fileprivate func resolveCurrentSession() throws -> AddressedSession {
        guard workout.block != nil else { throw ApplicationError.noBlock }
        guard let current = workout.currentSession, let id = current.address else {
            throw ApplicationError.notFound(.session, name: "current", candidates: orderedSessions().map(\.id.description))
        }
        return AddressedSession(id: id, model: current)
    }

    fileprivate func resolveSession(_ address: SessionAddress) throws -> AddressedSession {
        guard workout.block != nil else { throw ApplicationError.noBlock }
        let sessions = orderedSessions()
        guard let session = sessions.first(where: { $0.id == address }) else {
            throw ApplicationError.notFound(.session, name: address.description, candidates: sessions.map(\.id.description))
        }
        return session
    }

    fileprivate func resolveExercise(_ address: ExerciseAddress) throws -> Exercise {
        let session = try resolveSession(address.session).model
        guard !session.exercises.isEmpty else { throw ApplicationError.sessionUnavailable(address.session.description) }
        guard let exercise = session.exercises.first(where: { $0.order == address.order }) else {
            throw ApplicationError.notFound(
                .exercise,
                name: address.description,
                candidates: session.exercises.map(\.order).sorted().map { ExerciseAddress(session: address.session, order: $0).description }
            )
        }
        return exercise
    }

    func resolveSet(_ address: SetAddress) throws -> ExerciseSet {
        let exercise = try resolveExercise(address.exercise)
        guard let set = exercise.sets.first(where: { $0.index == address.index }) else {
            throw ApplicationError.notFound(
                .set,
                name: address.description,
                candidates: exercise.sets.map(\.index).sorted().map { SetAddress(exercise: address.exercise, index: $0).description }
            )
        }
        return set
    }
}
