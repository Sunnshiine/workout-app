import Foundation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {
    enum State: Equatable {
        case idle, syncing, offline, pendingWrites(Int), conflict([String])
    }
    private(set) var state: State = .idle

    private let client: any SheetsClient
    private let context: ModelContext
    private let sheetWritePlanner: SheetWritePlanner
    private let lastPerformedLookupRefresher: any LastPerformedLookupRefreshing
    private let lastPerformedBackfillObserver: any LastPerformedBackfillObserving
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
        lastPerformedLookupRefresher: any LastPerformedLookupRefreshing = NoopLastPerformedLookupRefresher(),
        lastPerformedBackfillObserver: any LastPerformedBackfillObserving = NoopLastPerformedBackfillObserver()
    ) {
        self.client = client
        self.context = context
        self.sheetWritePlanner = sheetWritePlanner
        self.lastPerformedLookupRefresher = lastPerformedLookupRefresher
        self.lastPerformedBackfillObserver = lastPerformedBackfillObserver
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

        let descriptor = FetchDescriptor<PendingWrite>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let pending = orderPendingWritesForFlush((try? context.fetch(descriptor)) ?? [])
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
            state = conflicts.isEmpty ? .idle : .conflict(conflicts)
        case .invalidated:
            state = .idle
        case .stoppedForRetry:
            break
        }
    }

    @discardableResult
    func sync(spreadsheetId: String) async -> Bool {
        state = .syncing
        print("[Sync] Starting sync for spreadsheetId: \(spreadsheetId)")

        await flushPending(spreadsheetId: spreadsheetId)
        let stateAfterFlush = state
        state = .syncing

        do {
            let titles = try await client.listTabTitles(spreadsheetId: spreadsheetId)
            print("[Sync] Tab titles: \(titles)")
            guard let tab = currentBlockTab(from: titles) else {
                print("[Sync] ERROR: No block tab matched from titles: \(titles)")
                state = .conflict(["No block tab found in the spreadsheet"])
                return false
            }
            print("[Sync] Selected tab: \(tab)")
            let snapshot = try await client.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tab)
            print("[Sync] Grid: \(snapshot.values.count) rows, first row: \(snapshot.values.first ?? [])")
            let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)
            print("[Sync] Parsed: \(parsed.block.weeks.count) weeks, warnings: \(parsed.warnings)")
            try replacePersistedBlock(with: BlockBuilder.makeBlock(from: parsed.block))
            let lastPerformedEntries = LastPerformedExtractor.entries(from: parsed.block)
            if !lastPerformedEntries.isEmpty {
                try LastPerformedIndex(context: context).ingest(lastPerformedEntries)
                lastPerformedLookupRefresher.refresh()
            }
            if case .conflict = stateAfterFlush {
                state = stateAfterFlush
            } else {
                state = parsed.warnings.isEmpty ? .idle : .conflict(parsed.warnings)
            }
            print("[Sync] Done, state: \(state)")
            launchLastPerformedBackfill(
                spreadsheetId: spreadsheetId,
                titles: titles,
                currentTab: tab,
                currentBlock: parsed.block
            )
            return true
        } catch {
            print("[Sync] ERROR: \(error)")
            state = .offline
            return false
        }
    }

    private func replacePersistedBlock(with block: Block) throws {
        overlayPendingWrites(on: block)
        for existing in try context.fetch(FetchDescriptor<Block>()) { context.delete(existing) }
        context.insert(block)
        try context.save()
    }

    private func overlayPendingWrites(on block: Block) {
        let writes = (try? context.fetch(FetchDescriptor<PendingWrite>())) ?? []
        for write in writes where write.blockTab == block.tabName && write.column == .notes {
            guard
                let set = findSet(
                    in: block,
                    week: write.week,
                    day: write.day,
                    exerciseName: write.exerciseName,
                    setIndex: write.setIndex
                )
            else { continue }

            if write.operation == .delete {
                set.state = .pending
                set.setLog = nil
            } else if write.valueToWrite?.caseInsensitiveCompare("skip") == .orderedSame {
                set.state = .skipped
                set.setLog = nil
            } else if let value = write.valueToWrite, let log = SetLog(formatted: value) {
                set.state = .logged
                set.setLog = log
            }
        }
    }

    private func findSet(
        in block: Block,
        week: Int,
        day: Int,
        exerciseName: String,
        setIndex: Int
    ) -> ExerciseSet? {
        block.weeks.first { $0.number == week }?
            .sessions.first { $0.dayNumber == day }?
            .exercises.first { $0.name == exerciseName }?
            .sets.first { $0.index == setIndex }
    }

    private func launchLastPerformedBackfill(
        spreadsheetId: String,
        titles: [String],
        currentTab: String,
        currentBlock: ParsedBlockModel
    ) {
        let historicalTabs = sortedHistoricalTabs(from: titles, excluding: currentTab)
        guard !historicalTabs.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            await backfillLastPerformed(
                spreadsheetId: spreadsheetId,
                currentBlock: currentBlock,
                historicalTabs: historicalTabs
            )
            lastPerformedBackfillObserver.lastPerformedBackfillDidFinish()
        }
    }

    private func backfillLastPerformed(
        spreadsheetId: String,
        currentBlock: ParsedBlockModel,
        historicalTabs: [String]
    ) async {
        let currentExercises = uniqueExercises(in: currentBlock)
        guard !currentExercises.isEmpty else { return }
        guard !hasLastPerformedCoverage(for: currentExercises) else { return }

        let client = client
        for tab in historicalTabs {
            let records: [LastPerformedRecord]
            do {
                records = try await Task.detached(priority: .background) {
                    try await Self.historicalLastPerformedRecords(
                        spreadsheetId: spreadsheetId,
                        tab: tab,
                        client: client
                    )
                }.value
            } catch {
                continue
            }

            if !records.isEmpty {
                do {
                    try LastPerformedIndex(context: context).ingest(records.map(\.entry))
                    lastPerformedLookupRefresher.refresh()
                } catch {
                    state = .conflict(["Last Performed backfill failed: \(error.localizedDescription)"])
                    return
                }
            }
            if hasLastPerformedCoverage(for: currentExercises) {
                return
            }
        }
    }

    nonisolated private static func historicalLastPerformedRecords(
        spreadsheetId: String,
        tab: String,
        client: any SheetsClient
    ) async throws -> [LastPerformedRecord] {
        let snapshot = try await client.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tab)
        let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)
        return LastPerformedExtractor.records(from: parsed.block)
    }

    private func uniqueExercises(in block: ParsedBlockModel) -> [(name: String, baseName: String)] {
        var seenNames = Set<String>()
        var exercises: [(name: String, baseName: String)] = []

        for week in block.weeks {
            for session in week.days {
                for exercise in session.exercises where seenNames.insert(exercise.name).inserted {
                    exercises.append((exercise.name, exercise.baseName))
                }
            }
        }

        return exercises
    }

    private func hasLastPerformedCoverage(for exercises: [(name: String, baseName: String)]) -> Bool {
        let index = LastPerformedIndex(context: context)
        return exercises.allSatisfy { exercise in
            index.lookup(exerciseName: exercise.name, baseName: exercise.baseName) != nil
        }
    }

}
extension SyncCoordinator: SheetSwitchSyncing {}
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

private struct PendingWriteFlushInvalidated: Error {}
private struct PendingWriteBatchFailed: Error {}
private struct PendingWriteFlushInProgress: Error {}

extension SyncCoordinator {
    func fetchPendingWriteRecords() throws -> [PendingWrite] {
        let descriptor = FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
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
            } catch is PendingWriteFlushInvalidated {
                return .invalidated
            } catch is PendingWriteBatchFailed {
                return .stoppedForRetry
            } catch let error as SheetWriterError {
                let message = recordConflict(error, for: write)
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
        } catch is PendingWriteFlushInvalidated {
            return .invalidated
        } catch is PendingWriteBatchFailed {
            return .stoppedForRetry
        } catch {
            state = .pendingWrites(pending.count)
            return .stoppedForRetry
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

    fileprivate func recordConflict(_ error: SheetWriterError, for write: PendingWrite) -> String {
        let message = error.errorDescription ?? String(describing: error)
        write.markConflict(message)
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
        let target = try flushContext.planner.target(for: request, in: snapshot)

        do {
            let update = try flushContext.planner.plan(request, target: target, in: snapshot)
            return PlannedPendingWrite(write: write, update: update, snapshot: snapshot)
        } catch let planningError as SheetWriterError where batch.overlaps(target) {
            try await flush(batch, context: flushContext)
            batch.removeAll()
            snapshot = try await gridSnapshot(for: request.blockTab, context: flushContext, snapshots: &snapshots)
            do {
                let update = try flushContext.planner.plan(request, target: target, in: snapshot)
                return PlannedPendingWrite(write: write, update: update, snapshot: snapshot)
            } catch let replannedError as SheetWriterError {
                throw replannedError
            } catch {
                throw planningError
            }
        }
    }

    fileprivate func flush(
        _ batch: PendingWriteBatch,
        context flushContext: PendingWriteFlushContext
    ) async throws {
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
            throw PendingWriteBatchFailed()
        }
        try ensurePendingWriteFlushIsCurrent(flushContext.generation)
        for item in batch.items {
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

    fileprivate func ensurePendingWriteFlushIsCurrent(_ generation: Int) throws {
        guard generation == pendingWriteFlushGeneration else {
            throw PendingWriteFlushInvalidated()
        }
    }
}
