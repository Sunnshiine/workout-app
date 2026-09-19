import Foundation
import OSLog
import SwiftData

private let syncLogger = Logger(subsystem: "WorkoutTracker", category: "Sync")

@MainActor
@Observable
final class SyncCoordinator {
    enum State: Equatable {
        case idle, syncing, offline
        case pendingWrites(Int)
        case conflict([String])

        /// What a sync step reports when it finishes: no messages means it left the coach nothing
        /// to resolve.
        init(messages: [String]) {
            self = messages.isEmpty ? .idle : .conflict(messages)
        }
    }
    private(set) var state: State = .idle

    private let client: any SheetsClient
    private let context: ModelContext
    private let sheetWritePlanner: SheetWritePlanner
    private let lastPerformed: any LastPerformedIndexing
    private let historyFill: ExerciseHistoryFill?
    /// The Exercise History fill the most recent successful sync launched, awaitable by whoever
    /// wants its outcome. Sync itself never waits (#558 leaves `workout sync` reporting to a
    /// follow-up).
    private(set) var inFlightHistoryFill: Task<ExerciseHistoryFill.Outcome, Never>?
    private var activeSyncCount = 0
    private var activePendingWriteFlushCount = 0
    private var pendingWriteFlushGeneration = 0

    func hasPendingWrites() throws -> Bool {
        guard activePendingWriteFlushCount == 0 else {
            throw PendingWriteFlushInProgress()
        }
        return try !fetchPendingWriteRecords().isEmpty
    }

    init(
        client: any SheetsClient,
        context: ModelContext,
        sheetWritePlanner: SheetWritePlanner = SheetWritePlanner(),
        lastPerformed: any LastPerformedIndexing = NoopLastPerformedIndex(),
        historyFill: ExerciseHistoryFill? = nil
    ) {
        self.client = client
        self.context = context
        self.sheetWritePlanner = sheetWritePlanner
        self.lastPerformed = lastPerformed
        self.historyFill = historyFill
    }

    /// The queued writes a flush will attempt, in the order it attempts them: oldest first, with
    /// each Set's Last Set RPE behind the Set Log it depends on.
    private func pendingWriteFlushQueue() -> [PendingWrite] {
        let descriptor = FetchDescriptor<PendingWrite>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return orderPendingWritesForFlush((try? context.fetch(descriptor)) ?? [])
    }

    func reportLocalWriteFailure(_ error: any Error) {
        state = .conflict(["Local write failed: \(error.localizedDescription)"])
    }

    func discardPendingWrites() async throws {
        guard activePendingWriteFlushCount == 0 else {
            throw PendingWriteFlushInProgress()
        }
        pendingWriteFlushGeneration += 1
        do {
            for write in try fetchPendingWriteRecords() {
                context.delete(write)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        state = .idle
    }

    func flushPending(spreadsheetId: String) async {
        let generation = beginPendingWriteFlush()
        defer { endPendingWriteFlush() }

        let pending = pendingWriteFlushQueue()
        guard !pending.isEmpty else {
            state = .idle
            return
        }

        state = .syncing
        let writer = SheetWriter(client: client)
        let flushContext = PendingWriteFlushContext(
            spreadsheetId: spreadsheetId,
            generation: generation,
            writer: writer,
            planner: sheetWritePlanner
        )

        let result = await flushPendingWrites(pending, context: flushContext)
        switch result {
        case .completed(let conflicts):
            try? context.save()
            state = State(messages: conflicts)
        case .invalidated:
            state = .idle
        case .stoppedForRetry:
            break
        }
    }

    @discardableResult
    func sync(spreadsheetId: String) async -> Bool {
        activeSyncCount += 1
        defer { activeSyncCount -= 1 }

        state = .syncing
        syncLogger.info("Starting sync for spreadsheetId: \(spreadsheetId, privacy: .public)")

        await flushPending(spreadsheetId: spreadsheetId)
        let stateAfterFlush = state
        state = .syncing

        do {
            let titles = try await client.listTabTitles(spreadsheetId: spreadsheetId)
            syncLogger.debug("Tab titles: \(titles, privacy: .public)")
            guard let tab = currentBlockTab(from: titles) else {
                syncLogger.error("No block tab matched from titles: \(titles, privacy: .public)")
                state = .conflict(["No block tab found in the spreadsheet"])
                return false
            }
            syncLogger.debug("Selected tab: \(tab, privacy: .public)")
            let snapshot = try await client.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tab)
            syncLogger.debug("Grid: \(snapshot.values.count) rows")
            let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)
            syncLogger.debug("Parsed: \(parsed.block.weeks.count) weeks, warnings: \(parsed.warnings, privacy: .public)")
            try replacePersistedBlock(with: BlockBuilder.makeBlock(from: parsed.block))
            let lastPerformedEntries = LastPerformedExtractor.entries(from: parsed.block)
            if !lastPerformedEntries.isEmpty {
                try lastPerformed.ingest(lastPerformedEntries)
            }
            if case .conflict = stateAfterFlush {
                state = stateAfterFlush
            } else {
                state = State(messages: parsed.warnings)
            }
            syncLogger.info("Done, state: \(String(describing: self.state), privacy: .public)")
            launchHistoryFill(
                ExerciseHistoryFill.Request(
                    spreadsheetId: spreadsheetId,
                    tabTitles: titles,
                    currentTab: tab,
                    baseNames: parsed.block.exerciseBaseNames
                )
            )
            return true
        } catch {
            syncLogger.error("Sync failed: \(String(describing: error), privacy: .public)")
            state = .offline
            return false
        }
    }

    private func replacePersistedBlock(with block: Block) throws {
        let loggedAtBySet = try localLoggedAtBySetID()
        overlayPendingWrites(on: block)
        preserveLocalLoggedAt(on: block, loggedAtBySet: loggedAtBySet)
        for existing in try context.fetch(FetchDescriptor<Block>()) { context.delete(existing) }
        context.insert(block)
        try context.save()
    }

    private func overlayPendingWrites(on block: Block) {
        let writes = (try? context.fetch(FetchDescriptor<PendingWrite>())) ?? []
        let sets = block.setsByID
        for write in writes where write.blockTab == block.tabName && write.column == .notes {
            sets[SetCoordinates.ID(write)]?.apply(write)
        }
    }

    /// Only an index refusal is the athlete's business today; #514 decides where background-index
    /// errors go.
    private func launchHistoryFill(_ request: ExerciseHistoryFill.Request) {
        guard let historyFill else { return }
        inFlightHistoryFill = Task { [weak self] in
            let outcome = await historyFill.run(request)
            if case .halted(_, .indexRejected(let message), _) = outcome {
                self?.state = .conflict(["Exercise History fill failed: \(message)"])
            }
            return outcome
        }
    }
}

extension SyncCoordinator {
    fileprivate func localLoggedAtBySetID() throws -> [SetCoordinates.ID: Date] {
        var values: [SetCoordinates.ID: Date] = [:]
        for block in try context.fetch(FetchDescriptor<Block>()) {
            for (id, set) in block.setsByID {
                guard let loggedAt = set.loggedAt else { continue }
                values[id] = loggedAt
            }
        }
        return values
    }

    fileprivate func preserveLocalLoggedAt(on block: Block, loggedAtBySet: [SetCoordinates.ID: Date]) {
        for (id, set) in block.setsByID where set.state == .logged {
            set.loggedAt = loggedAtBySet[id]
        }
    }
}

extension SyncCoordinator: SheetSwitchSyncing {
    /// `state` is the banner's, and a `flushPending` that overlaps a sync overwrites it with the
    /// flush's own verdict, which is why this does not read it (#585).
    var isSyncing: Bool { activeSyncCount > 0 || activePendingWriteFlushCount > 0 }
}

private struct PendingWriteFlushContext {
    let spreadsheetId: String
    let generation: Int
    let writer: SheetWriter
    let planner: SheetWritePlanner
}

private enum PendingWriteFlushResult {
    case completed(conflicts: [String])
    case invalidated
    case stoppedForRetry
}

private struct PlannedPendingWrite {
    let write: PendingWrite
    let update: SheetCellUpdate
    let snapshot: SheetWritePlanningSnapshot
    let auditDetails: SheetWriteAuditDetails
}

private struct PendingWriteBatch {
    private(set) var items: [PlannedPendingWrite] = []

    var isEmpty: Bool {
        items.isEmpty
    }

    var updates: [SheetCellUpdate] {
        items.map(\.update)
    }

    mutating func append(_ item: PlannedPendingWrite) {
        items.append(item)
    }

    mutating func removeAll() {
        items.removeAll()
    }

    func overlaps(_ target: SheetWriteTarget) -> Bool {
        items.contains { $0.update.target == target }
    }
}

/// The two ways a flush stops before it reaches the end of the queue. Each one already left the
/// store consistent, so the only thing left to decide is what the flush reports.
private enum PendingWriteFlushInterruption: Error {
    /// A newer flush generation superseded this one.
    case invalidated
    /// A batch write failed and its writes stay queued for the next attempt.
    case batchFailed

    var result: PendingWriteFlushResult {
        switch self {
        case .invalidated: .invalidated
        case .batchFailed: .stoppedForRetry
        }
    }
}

private struct PendingWriteFlushInProgress: Error {}
private struct PendingWritePlanningConflict: Error {
    let error: SheetWriterError
    let request: SheetWriteRequest
    let snapshot: SheetWritePlanningSnapshot
    let target: SheetWriteTarget?
}

extension SyncCoordinator {
    func fetchPendingWriteRecords() throws -> [PendingWrite] {
        let descriptor = FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
    }

    func fetchWriteTargetAuditRecords() throws -> [WriteTargetAuditEntry] {
        var descriptor = FetchDescriptor<WriteTargetAuditEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = WriteTargetAuditEntry.limit
        return try context.fetch(descriptor)
    }

    func clearWriteTargetAuditLog() throws {
        do {
            for entry in try context.fetch(FetchDescriptor<WriteTargetAuditEntry>()) {
                context.delete(entry)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    fileprivate func flushPendingWrites(
        _ pending: [PendingWrite],
        context flushContext: PendingWriteFlushContext
    ) async -> PendingWriteFlushResult {
        var snapshots: [String: SheetWritePlanningSnapshot] = [:]
        var conflicts: [String] = []
        var batch = PendingWriteBatch()

        for write in pending {
            guard write.status == .pending else { continue }
            do {
                let plannedWrite = try await plan(
                    write,
                    context: flushContext,
                    snapshots: &snapshots,
                    batch: &batch
                )
                try await append(
                    plannedWrite,
                    to: &batch,
                    snapshots: &snapshots,
                    context: flushContext
                )
            } catch let interruption as PendingWriteFlushInterruption {
                return interruption.result
            } catch let planningConflict as PendingWritePlanningConflict {
                let message = recordConflict(planningConflict, for: write, planner: flushContext.planner)
                conflicts.append(message)
                conflicts.append(contentsOf: recordDependentLastSetRPEConflicts(message, for: write, in: pending))
            } catch {
                recordRetry(for: write, error: error, pendingCount: pending.count)
                return .stoppedForRetry
            }
        }

        do {
            try await flush(batch, context: flushContext)
            return .completed(conflicts: conflicts)
        } catch {
            return error.result
        }
    }

    fileprivate func append(
        _ plannedWrite: PlannedPendingWrite,
        to batch: inout PendingWriteBatch,
        snapshots: inout [String: SheetWritePlanningSnapshot],
        context flushContext: PendingWriteFlushContext
    ) async throws {
        if batch.overlaps(plannedWrite.update.target) {
            try await flush(batch, context: flushContext)
            batch.removeAll()
        }
        batch.append(plannedWrite)
        snapshots[plannedWrite.update.tabName] = flushContext.planner.applying(
            plannedWrite.update,
            to: plannedWrite.snapshot
        )
    }

    fileprivate func recordConflict(
        _ conflict: PendingWritePlanningConflict,
        for write: PendingWrite,
        planner: SheetWritePlanner
    ) -> String {
        let message = conflict.error.errorDescription ?? String(describing: conflict.error)
        write.markConflict(message)
        recordWriteTargetAudit(
            for: write,
            details: planner.auditDetails(
                for: conflict.request,
                error: conflict.error,
                in: conflict.snapshot,
                target: conflict.target
            ),
            finalStatus: .conflict,
            message: message
        )
        return "\(write.exerciseName): \(message)"
    }

    fileprivate func recordRetry(for write: PendingWrite, error: any Error, pendingCount: Int) {
        write.retryCount += 1
        write.lastError = String(describing: error)
        try? context.save()
        state = .pendingWrites(pendingCount)
    }

    fileprivate func plan(
        _ write: PendingWrite,
        context flushContext: PendingWriteFlushContext,
        snapshots: inout [String: SheetWritePlanningSnapshot],
        batch: inout PendingWriteBatch
    ) async throws -> PlannedPendingWrite {
        try ensurePendingWriteFlushIsCurrent(flushContext.generation)
        let request = SheetWriteRequest(write)
        var snapshot = try await gridSnapshot(for: request.blockTab, context: flushContext, snapshots: &snapshots)
        let target: SheetWriteTarget
        do {
            target = try flushContext.planner.target(for: request, in: snapshot)
        } catch let error as SheetWriterError {
            throw PendingWritePlanningConflict(error: error, request: request, snapshot: snapshot, target: nil)
        }

        do {
            let update = try flushContext.planner.plan(request, target: target, in: snapshot)
            return PlannedPendingWrite(
                write: write,
                update: update,
                snapshot: snapshot,
                auditDetails: flushContext.planner.auditDetails(for: request, target: target, in: snapshot)
            )
        } catch is SheetWriterError where batch.overlaps(target) {
            try await flush(batch, context: flushContext)
            batch.removeAll()
            snapshot = try await gridSnapshot(for: request.blockTab, context: flushContext, snapshots: &snapshots)
            do {
                let update = try flushContext.planner.plan(request, target: target, in: snapshot)
                return PlannedPendingWrite(
                    write: write,
                    update: update,
                    snapshot: snapshot,
                    auditDetails: flushContext.planner.auditDetails(for: request, target: target, in: snapshot)
                )
            } catch let replannedError as SheetWriterError {
                throw PendingWritePlanningConflict(
                    error: replannedError,
                    request: request,
                    snapshot: snapshot,
                    target: target
                )
            }
        } catch let planningError as SheetWriterError {
            throw PendingWritePlanningConflict(error: planningError, request: request, snapshot: snapshot, target: target)
        }
    }

    fileprivate func flush(
        _ batch: PendingWriteBatch,
        context flushContext: PendingWriteFlushContext
    ) async throws(PendingWriteFlushInterruption) {
        guard !batch.isEmpty else { return }
        try ensurePendingWriteFlushIsCurrent(flushContext.generation)
        do {
            try await flushContext.writer.write(batch.updates, spreadsheetId: flushContext.spreadsheetId)
        } catch {
            for item in batch.items {
                item.write.retryCount += 1
                item.write.lastError = String(describing: error)
            }
            try? context.save()
            state = .pendingWrites((try? fetchPendingWriteRecords().count) ?? batch.items.count)
            throw .batchFailed
        }
        try ensurePendingWriteFlushIsCurrent(flushContext.generation)
        for item in batch.items {
            recordWriteTargetAudit(
                for: item.write,
                details: item.auditDetails,
                finalStatus: .succeeded,
                message: nil
            )
            context.delete(item.write)
        }
        try? context.save()
    }

    fileprivate func gridSnapshot(
        for tab: String,
        context flushContext: PendingWriteFlushContext,
        snapshots: inout [String: SheetWritePlanningSnapshot]
    ) async throws -> SheetWritePlanningSnapshot {
        if let snapshot = snapshots[tab] {
            return snapshot
        }

        let sheetSnapshot = try await client.fetchTabSnapshot(spreadsheetId: flushContext.spreadsheetId, tabName: tab)
        try ensurePendingWriteFlushIsCurrent(flushContext.generation)
        let snapshot = flushContext.planner.snapshot(for: sheetSnapshot)
        snapshots[tab] = snapshot
        return snapshot
    }

    fileprivate func beginPendingWriteFlush() -> Int {
        activePendingWriteFlushCount += 1
        return pendingWriteFlushGeneration
    }

    fileprivate func endPendingWriteFlush() {
        activePendingWriteFlushCount -= 1
    }

    fileprivate func ensurePendingWriteFlushIsCurrent(
        _ generation: Int
    ) throws(PendingWriteFlushInterruption) {
        guard generation == pendingWriteFlushGeneration else {
            throw .invalidated
        }
    }

    func recordWriteTargetAudit(
        for write: PendingWrite,
        details: SheetWriteAuditDetails,
        finalStatus: WriteTargetAuditStatus,
        message: String?
    ) {
        context.insert(
            WriteTargetAuditEntry(
                blockTab: write.blockTab,
                week: write.week,
                day: write.day,
                exerciseName: write.exerciseName,
                setIndex: write.setIndex,
                column: write.column,
                selectedA1Target: details.selectedA1Target,
                rowScanDetails: details.rowScanDetails,
                expectedCurrentValue: write.expectedCurrentValue,
                currentValue: details.currentValue,
                valueCheckOutcome: details.valueCheckOutcome,
                finalStatus: finalStatus,
                message: message
            )
        )
        pruneWriteTargetAuditLog()
    }

    func recordWriteTargetAuditConflictWithoutPlanning(for write: PendingWrite, message: String) {
        recordWriteTargetAudit(
            for: write,
            details: SheetWriteAuditDetails(
                selectedA1Target: nil,
                rowScanDetails: "Not evaluated: paired Set Log failed before this write was planned.",
                currentValue: nil,
                valueCheckOutcome: "Not checked because no target was selected."
            ),
            finalStatus: .conflict,
            message: message
        )
    }

    func pruneWriteTargetAuditLog() {
        var descriptor = FetchDescriptor<WriteTargetAuditEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = WriteTargetAuditEntry.limit + 1
        guard let entries = try? context.fetch(descriptor), entries.count > WriteTargetAuditEntry.limit else { return }
        for entry in entries.dropFirst(WriteTargetAuditEntry.limit) {
            context.delete(entry)
        }
    }
}
