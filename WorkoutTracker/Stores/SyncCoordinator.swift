import Foundation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {
    enum State: Equatable {
        case idle, syncing, offline
        case conflict([String])
    }
    private(set) var state: State = .idle

    private let client: any SheetsClient
    private let context: ModelContext

    init(client: any SheetsClient, context: ModelContext) {
        self.client = client
        self.context = context
    }

    func sync(spreadsheetId: String) async {
        state = .syncing
        print("[Sync] Starting sync for spreadsheetId: \(spreadsheetId)")
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
            state = parsed.warnings.isEmpty ? .idle : .conflict(parsed.warnings)
            print("[Sync] Done, state: \(state)")
        } catch {
            print("[Sync] ERROR: \(error)")
            state = .offline
        }
    }

    private func replacePersistedBlock(with block: Block) {
        for existing in (try? context.fetch(FetchDescriptor<Block>())) ?? [] { context.delete(existing) }
        context.insert(block)
        try? context.save()
    }
}
