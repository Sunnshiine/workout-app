import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func namedWorkoutScenariosCoverFixtureContract() throws {
    #expect(
        WorkoutScenarios.names == [
            "fresh configured app",
            "current session with pending sets",
            "partially logged session",
            "open exercises",
            "sync failure",
            "queued write",
            "block overview with mixed session states",
            "partially uploaded block"
        ]
    )

    let fresh = try WorkoutScenarios.freshConfiguredApp()
    defer { withExtendedLifetime(fresh.container) {} }
    #expect(fresh.settings.isConfigured)
    #expect(fresh.store.displayedSession?.week?.number == 1)
    #expect(fresh.store.displayedSession?.dayNumber == 1)

    let pending = WorkoutScenarios.currentSessionWithPendingSets()
    #expect(pending.currentSession?.dayNumber == 1)
    #expect(pending.currentSession?.exercises.flatMap(\.sets).allSatisfy { $0.state == .pending } == true)

    let partiallyLogged = WorkoutScenarios.partiallyLoggedSession()
    let partiallyLoggedStates = partiallyLogged.currentSession?.exercises.flatMap(\.sets).map(\.state) ?? []
    #expect(partiallyLoggedStates.contains(.logged))
    #expect(partiallyLoggedStates.contains(.pending))

    let open = WorkoutScenarios.openExercises()
    let openExerciseNames = open.tracker.openExercises(
        in: open.block,
        currentSession: try #require(open.currentSession)
    ).map(\.name)
    #expect(openExerciseNames == ["Back Squat", "Bench Press"])

    let failure = try #require(SyncStatusBannerPresentation(state: WorkoutScenarios.syncFailure()))
    #expect(failure.text == "Sheet write failed")

    let queuedWrite = WorkoutScenarios.queuedWrite()
    #expect(queuedWrite.blockTab == "Block 27")
    #expect(queuedWrite.exerciseName == "Back Squat")
    #expect(queuedWrite.valueToWrite == "185x5@8")

    let overview = WorkoutScenarios.blockOverviewWithMixedSessionStates()
    let presentation = BlockOverviewPresentation(block: overview.block, currentSession: overview.currentSession)
    #expect(presentation.tiles.map(\.state) == [.complete, .incomplete, .current, .incomplete])

    let partiallyUploaded = WorkoutScenarios.partiallyUploadedBlock()
    let partialPresentation = BlockOverviewPresentation(
        block: partiallyUploaded.block,
        currentSession: partiallyUploaded.currentSession
    )
    #expect(partialPresentation.tiles.count == 16)
    #expect(partialPresentation.tiles.filter { $0.state == .unavailable }.count == 11)
}
