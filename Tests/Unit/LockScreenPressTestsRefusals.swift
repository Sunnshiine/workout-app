import Foundation
import Testing

@testable import WorkoutTracker

private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

/// The app's mic records in the app, so a stale chip over it says why even with no rest, and the
/// mic keeps listening.
@MainActor
@Test func aChipWhileTheAppsMicListensOverNoRestSaysSoAndTheMicListensOn() async throws {
    let harness = try await BackgroundDictationHarness(
        transcriber: OpenMicTranscriber(holdingStart: false, failingToStart: nil),
        reading: .heard("", segments: [])
    )
    let session = try #require(harness.app.workout.currentSession)
    let active = try #require(harness.focus.activeSet(in: session)).setID
    try #require(harness.dictation.start(for: active))

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.micBusy(.card)))
    #expect(harness.liveActivity.readbacks == [.notLogged("The app’s mic is listening. Open to log")])
    #expect(harness.liveActivity.replacements.isEmpty)
    #expect(harness.dictation.state.pressSetID == active)
    try harness.expectNothingWritten()
    await harness.dictation.cancel()
}

/// A press from another Session, once every Set of this one is logged, names no Set here, so it
/// reads back over nothing of this Session.
@MainActor
@Test func aPressFromAnotherSessionOnAFinishedSessionSaysNoSetIsLeft() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let sets = SessionSetOrder.orderedSets(in: session)
    for position in sets {
        try harness.app.workout.log(position.set, as: logged235)
    }
    harness.focus.reset(to: session)
    let lastSetOfBlock26 = harness.identity(of: try #require(sets.last).setID, blockTab: "Block 26")

    let outcome = await harness.press(lastSetOfBlock26)

    #expect(outcome == .notLogged(.sessionChanged))
    #expect(harness.liveActivity.noSets == [.noSetLeft])
    #expect(harness.liveActivity.readbacks.isEmpty)
}
