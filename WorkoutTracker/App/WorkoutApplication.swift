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
