import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
struct ConfiguredAppScenario {
    let container: ModelContainer
    let context: ModelContext
    let settings: SettingsStore
    let store: WorkoutStore
}

@MainActor
struct BlockScenario {
    let block: Block
    let currentSession: Session?
    let tracker = SessionProgressTracker()
}

enum WorkoutScenarios {
    static let names = [
        "fresh configured app",
        "current session with pending sets",
        "partially logged session",
        "open exercises",
        "sync failure",
        "queued write",
        "block overview with mixed session states",
        "partially uploaded block"
    ]

    @MainActor
    static func freshConfiguredApp() throws -> ConfiguredAppScenario {
        let container = try ModelContainer(
            for: Block.self,
            PendingWrite.self,
            WriteTargetAuditEntry.self,
            LastPerformedEntry.self,
            configurations: ModelConfiguration(
                "fresh-configured-\(UUID().uuidString)",
                isStoredInMemoryOnly: true
            )
        )
        let context = container.mainContext
        context.insert(WorkoutFixtureScenarios.currentSessionWithPendingSetsBlock())
        try context.save()

        let settings = SettingsStore(defaults: try makeDefaults())
        settings.isSignedIn = true
        settings.setSheetURL(WorkoutFixtureScenarios.sheetURL)

        let store = WorkoutStore(context: context, defaults: try makeDefaults())
        store.reload()
        return ConfiguredAppScenario(container: container, context: context, settings: settings, store: store)
    }

    @MainActor
    static func currentSessionWithPendingSets() -> BlockScenario {
        scenario(from: WorkoutFixtureScenarios.currentSessionWithPendingSetsBlock())
    }

    @MainActor
    static func partiallyLoggedSession() -> BlockScenario {
        scenario(from: WorkoutFixtureScenarios.partiallyLoggedSessionBlock())
    }

    @MainActor
    static func openExercises() -> BlockScenario {
        scenario(from: WorkoutFixtureScenarios.openExercisesBlock())
    }

    static func syncFailure() -> SyncCoordinator.State {
        WorkoutFixtureScenarios.syncFailureState()
    }

    static func queuedWrite() -> PendingWrite {
        WorkoutFixtureScenarios.queuedWrite()
    }

    @MainActor
    static func blockOverviewWithMixedSessionStates() -> BlockScenario {
        let block = WorkoutFixtureScenarios.blockOverviewWithMixedSessionStatesBlock()
        let currentSession = block.weeks
            .first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == 3 }
        return BlockScenario(block: block, currentSession: currentSession)
    }

    @MainActor
    static func partiallyUploadedBlock() -> BlockScenario {
        scenario(from: WorkoutFixtureScenarios.partiallyUploadedBlock())
    }

    @MainActor
    private static func scenario(from block: Block) -> BlockScenario {
        let currentSession = SessionProgressTracker().currentSession(in: block)
        return BlockScenario(block: block, currentSession: currentSession)
    }

    @MainActor
    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "scenario.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
