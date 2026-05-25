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
        do {
            let titles = try await client.listTabTitles(spreadsheetId: spreadsheetId)
            guard let tab = currentBlockTab(from: titles) else {
                state = .conflict(["No block tab found in the spreadsheet"])
                return
            }
            let grid = try await client.fetchTab(spreadsheetId: spreadsheetId, tabName: tab)
            let parsed = SheetParser().parse(grid: grid, tabName: tab)
            replacePersistedBlock(with: BlockBuilder.makeBlock(from: parsed.block))
            state = parsed.warnings.isEmpty ? .idle : .conflict(parsed.warnings)
        } catch {
            state = .offline
        }
    }

    private func replacePersistedBlock(with block: Block) {
        for existing in (try? context.fetch(FetchDescriptor<Block>())) ?? [] { context.delete(existing) }
        context.insert(block)
        try? context.save()
    }
}
