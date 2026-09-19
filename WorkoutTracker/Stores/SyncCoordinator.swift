import Foundation
import OSLog
import SwiftData

private let syncLogger = Logger(subsystem: "WorkoutTracker", category: "Sync")

@MainActor
@Observable
final class SyncCoordinator {
    /// What the last finished step concluded.
    private(set) var outcome: SyncOutcome = .clear

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
        outcome = .localWriteFailed(error.localizedDescription)
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
        outcome = .clear
    }

    func flushPending(spreadsheetId: String) async {
        outcome = await flushQueue(spreadsheetId: spreadsheetId)
    }

    private func flushQueue(spreadsheetId: String) async -> SyncOutcome {
        let generation = beginPendingWriteFlush()
        defer { endPendingWriteFlush() }

        let pending = pendingWriteFlushQueue()
        guard !pending.isEmpty else { return .clear }

        let writer = SheetWriter(client: client)
        let flushContext = PendingWriteFlushContext(
            spreadsheetId: spreadsheetId,
            generation: generation,
            writer: writer,
            planner: sheetWritePlanner
        )

        switch await flushPendingWrites(pending, context: flushContext) {
        case .completed(let conflicts):
            try? context.save()
            return SyncOutcome(refusedWrites: conflicts)
        case .invalidated:
            return .clear
        case .stoppedForRetry(let queued):
            return .writesQueued(queued)
        }
    }

    @discardableResult
    func sync(spreadsheetId: String) async -> Bool {
        activeSyncCount += 1
        defer { activeSyncCount -= 1 }

        syncLogger.info("Starting sync for spreadsheetId: \(spreadsheetId, privacy: .public)")

        let flushOutcome = await flushQueue(spreadsheetId: spreadsheetId)

        do {
            let titles = try await client.listTabTitles(spreadsheetId: spreadsheetId)
            syncLogger.debug("Tab titles: \(titles, privacy: .public)")
            guard let tab = currentBlockTab(from: titles) else {
                syncLogger.error("No block tab matched from titles: \(titles, privacy: .public)")
                outcome = .sync(sheetRead: .noBlockTab, flush: flushOutcome)
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
            outcome = .sync(sheetRead: SyncOutcome(parseWarnings: parsed.warnings), flush: flushOutcome)
            syncLogger.info("Done, outcome: \(String(describing: self.outcome), privacy: .public)")
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
            outcome = .sync(sheetRead: .sheetUnreachable, flush: flushOutcome)
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

    /// Only an index refusal is the athlete's business: it leaves Exercise History short and the
    /// next sync comes straight back to the same tab.
    private func launchHistoryFill(_ request: ExerciseHistoryFill.Request) {
        guard let historyFill else { return }
        inFlightHistoryFill = Task { [weak self] in
            let fillOutcome = await historyFill.run(request)
            if case .halted(_, .indexRejected(let message), _) = fillOutcome {
                self?.outcome = .historyFillFailed(message)
            }
            return fillOutcome
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
    var isSyncing: Bool { activeSyncCount > 0 || activePendingWriteFlushCount > 0 }
}

extension SyncCoordinator {
    /// The flattened reading the `workout` CLI still prints, where every outcome that wants the
    /// athlete collapses into one `.conflict`. `SyncStateSnapshot`'s JSON is a contract; #590
    /// migrates it and retires this.
    enum State: Equatable {
        case idle, syncing, offline
        case pendingWrites(Int)
        case conflict([String])

        /// Every sentence the CLI prints is composed here and nowhere else.
        init(_ outcome: SyncOutcome) {
            self =
                switch outcome {
                case .clear: .idle
                case .sheetUnreachable: .offline
                case .writesQueued(let count): .pendingWrites(count)
                case .localWriteFailed(let message): .conflict(["Local write failed: \(message)"])
                case .writesRefused(let messages): .conflict(messages)
                case .noBlockTab: .conflict(["No block tab found in the spreadsheet"])
                case .parseWarnings(let warnings): .conflict(warnings)
                case .historyFillFailed(let message): .conflict(["Exercise History fill failed: \(message)"])
                }
        }
    }

    /// A running step outranks what the last one concluded, because a verdict the next moment may
    /// overturn is not worth showing.
    var state: State { isSyncing ? .syncing : State(outcome) }
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
    case stoppedForRetry(queued: Int)
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
    case batchFailed(queued: Int)

    var result: PendingWriteFlushResult {
        switch self {
        case .invalidated: .invalidated
        case .batchFailed(let queued): .stoppedForRetry(queued: queued)
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
                recordRetry(for: write, error: error)
                return .stoppedForRetry(queued: pending.count)
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

    fileprivate func recordRetry(for write: PendingWrite, error: any Error) {
        write.retryCount += 1
        write.lastError = String(describing: error)
        try? context.save()
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
            throw .batchFailed(queued: (try? fetchPendingWriteRecords().count) ?? batch.items.count)
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
