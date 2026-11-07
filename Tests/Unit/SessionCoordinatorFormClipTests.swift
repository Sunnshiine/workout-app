import Foundation
import Testing

@testable import WorkoutTracker

/// The card's seam: which Sets offer clips, and that a clip lands on the Set the athlete asked from
/// even when the card has moved on by the time the movie arrives.
@MainActor
@Suite struct SessionCoordinatorFormClipTests {
    @MainActor
    private struct Stage {
        let app: WorkoutApplication
        let coordinator: SessionCoordinator
        let first: ExerciseSet
        let second: ExerciseSet

        init() async throws {
            let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
            app = try WorkoutApplication(
                environment: .inMemory(
                    sheets: LocalWorkbookSheetsClient(workbook: WorkbookScenario.freshBlock.workbook()),
                    formClips: directory,
                    now: { Date(timeIntervalSince1970: 1_780_000_000) }
                )
            )
            _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
            let session = try #require(app.workout.currentSession)
            let exercise = try #require(session.exercises.first { $0.order == 0 })
            let sets = exercise.sets.sorted { $0.index < $1.index }
            first = sets[0]
            second = sets[1]
            let settings = app.settings
            coordinator = SessionCoordinator(
                session: session,
                wiring: .fixture(logging: app.workout, formClips: app.formClips, spreadsheetId: { settings.spreadsheetId })
            )
        }

        func slot(_ set: ExerciseSet, mode: SetCardSlot.Mode) -> SetCardSlot {
            SetCardSlot(set: set, ordinal: set.index + 1, count: 3, mode: mode, cardIdentity: "\(set.index)")
        }

        func movie() async throws -> URL {
            let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            try await SyntheticMovie.write(to: url, frames: 6) { _ in SyntheticMovie.Point(x: 0.5, y: 0.5) }
            return url
        }
    }

    @Test func onlyALoggedSetOffersClips() async throws {
        let stage = try await Stage()
        #expect(stage.coordinator.cardClips(for: stage.slot(stage.first, mode: .logging)) == nil)

        try stage.app.workout.skip(stage.second)
        #expect(stage.coordinator.cardClips(for: stage.slot(stage.second, mode: .logging)) == nil)

        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let offered = try #require(
            stage.coordinator.cardClips(for: stage.slot(stage.first, mode: .reviewingLogged(showsSavedConfirmation: false)))
        )
        #expect(offered.clips.isEmpty)
        #expect(!offered.isAdding)
    }

    @Test func noSheetOffersNoClips() async throws {
        let stage = try await Stage()
        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let unsheeted = SessionCoordinator(session: stage.first.exercise?.session, wiring: .fixture(logging: stage.app.workout))

        #expect(unsheeted.cardClips(for: stage.slot(stage.first, mode: .heldAfterSpokenWrite)) == nil)
    }

    @Test func theCameraThePickerAndAReviewEachGetTheirOwnCover() async throws {
        let stage = try await Stage()
        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let target = try #require(stage.coordinator.cardClips(for: stage.slot(stage.first, mode: .heldAfterSpokenWrite))?.target)

        let covers: [FormClipRequest] = [.add(target, .camera), .add(target, .photos), .review(UUID())]

        #expect(Set(covers.map(\.id)).count == covers.count)
    }

    @Test func aPickedMovieLandsOnTheSetItWasPickedForAndOpensTheReview() async throws {
        let stage = try await Stage()
        let coordinator = stage.coordinator
        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let held = stage.slot(stage.first, mode: .heldAfterSpokenWrite)
        let target = try #require(coordinator.cardClips(for: held)?.target)
        coordinator.requestClip(from: .photos, for: target)
        #expect(coordinator.clipRequest == .add(target, .photos))

        let movie = try await stage.movie()
        coordinator.addClip(to: target) { movie }
        #expect(coordinator.clipRequest == nil)
        #expect(coordinator.cardClips(for: held)?.isAdding == true)
        try stage.app.workout.log(stage.second, as: SetLog(weight: .pounds(190), reps: 5, rpe: .eight))

        await waitUntil({ coordinator.addingClipTo == nil && coordinator.clipRequest != nil }, orRecord: "the pick never landed")

        let clip = try #require(stage.app.formClips.clips.first)
        #expect(clip.setID == target.setID)
        #expect(coordinator.clipRequest == .review(clip.id))
        #expect(coordinator.cardClips(for: held)?.clips.map(\.id) == [clip.id])
        #expect(
            coordinator.cardClips(for: stage.slot(stage.second, mode: .reviewingLogged(showsSavedConfirmation: false)))?.clips.isEmpty
                == true
        )
    }

    @Test func aPickThatIsNoMovieSaysSoAndAddsNothing() async throws {
        let stage = try await Stage()
        let coordinator = stage.coordinator
        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let target = try #require(coordinator.cardClips(for: stage.slot(stage.first, mode: .heldAfterSpokenWrite))?.target)
        let notAMovie = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: notAMovie)

        coordinator.addClip(to: target) { notAMovie }
        await waitUntil({ coordinator.clipFailure != nil }, orRecord: "the failure never reached the stage")

        #expect(coordinator.clipFailure == FormClipError.notAMovie.failureMessage)
        #expect(coordinator.addingClipTo == nil)
        #expect(coordinator.clipRequest == nil)
        #expect(stage.app.formClips.clips.isEmpty)

        coordinator.dismissClipFailure()
        #expect(coordinator.clipFailure == nil)
    }

    @Test func aPickerThatChoseNothingEndsQuietly() async throws {
        let stage = try await Stage()
        let coordinator = stage.coordinator
        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let target = try #require(coordinator.cardClips(for: stage.slot(stage.first, mode: .heldAfterSpokenWrite))?.target)

        coordinator.addClip(to: target) { nil }
        await waitUntil({ coordinator.addingClipTo == nil }, orRecord: "the card kept showing work")

        #expect(coordinator.clipFailure == nil)
        #expect(coordinator.clipRequest == nil)
    }

    @Test func aLoadThatThrowsSaysSomethingPlain() async throws {
        let stage = try await Stage()
        let coordinator = stage.coordinator
        try stage.app.workout.log(stage.first, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
        let target = try #require(coordinator.cardClips(for: stage.slot(stage.first, mode: .heldAfterSpokenWrite))?.target)

        coordinator.addClip(to: target) { throw CocoaError(.fileReadUnknown) }
        await waitUntil({ coordinator.clipFailure != nil }, orRecord: "the failure never reached the stage")

        #expect(coordinator.clipFailure == "That clip couldn't be saved. Try it again.")
    }
}
