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

    init(client: any SheetsClient, context: ModelContext) {
        self.client = client
        self.context = context
    }

    func reportLocalWriteFailure(_ error: any Error) {
        state = .conflict(["Local write failed: \(error.localizedDescription)"])
    }

    func flushPending(spreadsheetId: String) async {
        let descriptor = FetchDescriptor<PendingWrite>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let pending = (try? context.fetch(descriptor)) ?? []
        guard !pending.isEmpty else {
            state = .idle
            return
        }

        state = .syncing
        let writer = SheetWriter(client: client)
        var conflicts: [String] = []

        for write in pending {
            do {
                try await writer.write(SheetWriteRequest(write), spreadsheetId: spreadsheetId)
                context.delete(write)
            } catch let error as SheetWriterError {
                let message = error.errorDescription ?? String(describing: error)
                write.markConflict(message)
                conflicts.append("\(write.exerciseName): \(message)")
            } catch {
                write.retryCount += 1
                write.lastError = String(describing: error)
                try? context.save()
                state = .pendingWrites(pending.count)
                return
            }
        }

        try? context.save()
        if conflicts.isEmpty {
            state = .idle
        } else {
            state = .conflict(conflicts)
        }
    }

    func sync(spreadsheetId: String) async {
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
                return
            }
            print("[Sync] Selected tab: \(tab)")
            let grid = try await client.fetchTab(spreadsheetId: spreadsheetId, tabName: tab)
            print("[Sync] Grid: \(grid.count) rows, first row: \(grid.first ?? [])")
            let parsed = SheetParser().parse(grid: grid, tabName: tab)
            print("[Sync] Parsed: \(parsed.block.weeks.count) weeks, warnings: \(parsed.warnings)")
            replacePersistedBlock(with: BlockBuilder.makeBlock(from: parsed.block))
            if case .conflict = stateAfterFlush {
                state = stateAfterFlush
            } else {
                state = parsed.warnings.isEmpty ? .idle : .conflict(parsed.warnings)
            }
            print("[Sync] Done, state: \(state)")
        } catch {
            print("[Sync] ERROR: \(error)")
            state = .offline
        }
    }

    private func replacePersistedBlock(with block: Block) {
        overlayPendingWrites(on: block)
        for existing in (try? context.fetch(FetchDescriptor<Block>())) ?? [] { context.delete(existing) }
        context.insert(block)
        try? context.save()
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
}
