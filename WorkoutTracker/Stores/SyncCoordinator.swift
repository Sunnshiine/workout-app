import Foundation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {
    enum State: Equatable {
        case idle, syncing, offline
        case pendingWrites(Int)
        case conflict([String])
    }
    private(set) var state: State = .idle

    private let client: any SheetsClient
    private let context: ModelContext
    private let sheetWritePlanner: SheetWritePlanner
    private let lastPerformedLookupRefresher: any LastPerformedLookupRefreshing
    private let lastPerformedBackfillObserver: any LastPerformedBackfillObserving
    private let tabFetchBackoff: SheetsBackoff
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
        lastPerformedBackfillObserver: any LastPerformedBackfillObserving = NoopLastPerformedBackfillObserver(),
        tabFetchBackoff: SheetsBackoff = SheetsBackoff()
    ) {
        self.client = client
        self.context = context
        self.sheetWritePlanner = sheetWritePlanner
        self.lastPerformedLookupRefresher = lastPerformedLookupRefresher
        self.lastPerformedBackfillObserver = lastPerformedBackfillObserver
        self.tabFetchBackoff = tabFetchBackoff
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
        let loggedAtBySet = try localLoggedAtBySetID()
        overlayPendingWrites(on: block)
        preserveLocalLoggedAt(on: block, loggedAtBySet: loggedAtBySet)
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
                set.loggedAt = nil
            } else if let value = write.valueToWrite {
                let classification = SetLogToken.classify(value)
                switch classification.state {
                case .skipped:
                    set.state = .skipped
                    set.setLog = nil
                    set.loggedAt = nil
                case .logged:
                    if let log = classification.setLog {
                        set.state = .logged
                        set.setLog = log
                    }
                case .pending:
                    break
                }
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

    /// The lazy backfill, made resumable and observable (ADR-0012, #365).
    ///
    /// A failed tab — a transient 429/5xx that outlasts the backoff budget, or any non-transient
    /// error — **halts** the fill instead of skipping it, because a silent hole in the middle
    /// corrupts the coverage count. The deepest tab read before the halt is persisted as a cursor
    /// so the next sync resumes from the tab just deeper than it; re-ingest is idempotent via
    /// `source` dedup, so the cursor only spares redundant reads. The cursor is cleared on a clean
    /// finish (coverage reached or tabs exhausted). Each ingested tab publishes per-tab progress.
    private func backfillLastPerformed(
        spreadsheetId: String,
        currentBlock: ParsedBlockModel,
        historicalTabs: [String]
    ) async {
        let currentExercises = uniqueExercises(in: currentBlock)
        guard !currentExercises.isEmpty else { return }
        guard !hasLastPerformedCoverage(for: currentExercises) else {
            clearHistoryFillCursor(spreadsheetId: spreadsheetId)
            return
        }

        let tabsToScan = resumeTabs(historicalTabs, after: historyFillCursorTab(spreadsheetId: spreadsheetId))
        let client = client
        let backoff = tabFetchBackoff
        var tabsCompleted = 0

        for tab in tabsToScan {
            let scan: HistoricalTabScan
            do {
                scan = try await Task.detached(priority: .background) {
                    try await Self.scanHistoricalTab(
                        spreadsheetId: spreadsheetId,
                        tab: tab,
                        client: client,
                        backoff: backoff
                    )
                }.value
            } catch {
                // A non-transient error (auth, malformed response) propagated: halt without a
                // silent skip, leaving the cursor so the next sync resumes at this tab.
                return
            }

            guard case let .ingested(records) = scan else {
                // `.failed`: the transient backoff budget was spent. Halt at this tab — the cursor
                // still points at the last success, so the next sync resumes here.
                return
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

            advanceHistoryFillCursor(spreadsheetId: spreadsheetId, to: tab)
            tabsCompleted += 1
            lastPerformedBackfillObserver.lastPerformedBackfillDidProgress(
                LastPerformedBackfillProgress(tab: tab, tabsCompleted: tabsCompleted, tabsToScan: tabsToScan.count)
            )

            if hasLastPerformedCoverage(for: currentExercises) {
                clearHistoryFillCursor(spreadsheetId: spreadsheetId)
                return
            }
        }

        // Tabs exhausted without reaching coverage: a clean finish, so start fresh next sync.
        clearHistoryFillCursor(spreadsheetId: spreadsheetId)
    }

    /// One historical tab's outcome, computed off the main actor.
    private enum HistoricalTabScan: Sendable {
        /// The tab was read (however small) and yielded these entry records.
        case ingested([LastPerformedRecord])
        /// The tab could not be read: a transient failure outlasted the backoff budget.
        case failed
    }

    nonisolated private static func scanHistoricalTab(
        spreadsheetId: String,
        tab: String,
        client: any SheetsClient,
        backoff: SheetsBackoff
    ) async throws -> HistoricalTabScan {
        switch try await client.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tab, retrying: backoff) {
        case .failed:
            return .failed
        case .fetched(let snapshot):
            let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)
            return .ingested(LastPerformedExtractor.records(from: parsed.block))
        }
    }

    /// The historical tabs still to read, given the persisted resume cursor. Everything at or newer
    /// than the deepest ingested tab is already on device, so the fill starts at the next tab deeper.
    private func resumeTabs(_ historicalTabs: [String], after cursorTab: String?) -> [String] {
        guard let cursorTab, let cursorNumber = blockNumber(from: cursorTab) else { return historicalTabs }
        return historicalTabs.filter { tab in
            guard let number = blockNumber(from: tab) else { return true }
            return number < cursorNumber
        }
    }

    private func historyFillCursorTab(spreadsheetId: String) -> String? {
        historyFillCursor(spreadsheetId: spreadsheetId)?.deepestIngestedTab
    }

    private func historyFillCursor(spreadsheetId: String) -> HistoryFillCursor? {
        let descriptor = FetchDescriptor<HistoryFillCursor>(
            predicate: #Predicate { $0.spreadsheetId == spreadsheetId }
        )
        return try? context.fetch(descriptor).first
    }

    private func advanceHistoryFillCursor(spreadsheetId: String, to tab: String) {
        if let existing = historyFillCursor(spreadsheetId: spreadsheetId) {
            existing.deepestIngestedTab = tab
            existing.updatedAt = .now
        } else {
            context.insert(HistoryFillCursor(spreadsheetId: spreadsheetId, deepestIngestedTab: tab))
        }
        try? context.save()
    }

    private func clearHistoryFillCursor(spreadsheetId: String) {
        guard let cursor = historyFillCursor(spreadsheetId: spreadsheetId) else { return }
        context.delete(cursor)
        try? context.save()
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

    /// The coverage-based stopping rule (ADR-0012): the fill reaches back until every
    /// current-Block Exercise has at least `historyCoverageTarget` entries counted per
    /// Cadence-stripped base name — the last ~5 entries the Exercise History sheet reads —
    /// or Block tabs are exhausted. Counting by base name (not Movement level) may fetch a
    /// tab Movement matching didn't strictly need; that over-fetch is accepted (#357).
    private static let historyCoverageTarget = 5

    private func hasLastPerformedCoverage(for exercises: [(name: String, baseName: String)]) -> Bool {
        let index = LastPerformedIndex(context: context)
        let baseNames = Set(exercises.map(\.baseName))
        return baseNames.allSatisfy { baseName in
            index.entryCount(baseName: baseName) >= Self.historyCoverageTarget
        }
    }

}

private struct LocalSetID: Hashable {
    let blockTab: String
    let week: Int
    let day: Int
    let exerciseName: String
    let setIndex: Int
}

private extension SyncCoordinator {
    func localLoggedAtBySetID() throws -> [LocalSetID: Date] {
        var values: [LocalSetID: Date] = [:]
        for block in try context.fetch(FetchDescriptor<Block>()) {
            for week in block.weeks {
                for session in week.sessions {
                    for exercise in session.exercises {
                        for set in exercise.sets {
                            guard let loggedAt = set.loggedAt else { continue }
                            values[
                                LocalSetID(
                                    blockTab: block.tabName,
                                    week: week.number,
                                    day: session.dayNumber,
                                    exerciseName: exercise.name,
                                    setIndex: set.index
                                )
                            ] = loggedAt
                        }
                    }
                }
            }
        }
        return values
    }

    func preserveLocalLoggedAt(on block: Block, loggedAtBySet: [LocalSetID: Date]) {
        for week in block.weeks {
            for session in week.sessions {
                for exercise in session.exercises {
                    for set in exercise.sets where set.state == .logged {
                        set.loggedAt = loggedAtBySet[
                            LocalSetID(
                                blockTab: block.tabName,
                                week: week.number,
                                day: session.dayNumber,
                                exerciseName: exercise.name,
                                setIndex: set.index
                            )
                        ]
                    }
                }
            }
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

private struct PendingWriteFlushInvalidated: Error {}
private struct PendingWriteBatchFailed: Error {}
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
            } catch is PendingWriteFlushInvalidated {
                return .invalidated
            } catch is PendingWriteBatchFailed {
                return .stoppedForRetry
            } catch let planningConflict as PendingWritePlanningConflict {
                let message = recordConflict(planningConflict, for: write, planner: flushContext.planner)
                conflicts.append(message)
                conflicts.append(contentsOf: recordDependentLastSetRPEConflicts(message, for: write, in: pending))
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
        recordWriteTargetAudit(
            for: write,
            details: SheetWriteAuditDetails(
                selectedA1Target: nil,
                rowScanDetails: "No row selected: \(message)",
                currentValue: nil,
                valueCheckOutcome: "Not checked because no target was selected."
            ),
            finalStatus: .conflict,
            message: message
        )
        return "\(write.exerciseName): \(message)"
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
        } catch let planningError as SheetWriterError where batch.overlaps(target) {
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
            } catch {
                throw planningError
            }
        } catch let planningError as SheetWriterError {
            throw PendingWritePlanningConflict(error: planningError, request: request, snapshot: snapshot, target: target)
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

    fileprivate func ensurePendingWriteFlushIsCurrent(_ generation: Int) throws {
        guard generation == pendingWriteFlushGeneration else {
            throw PendingWriteFlushInvalidated()
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
