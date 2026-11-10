import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)

/// The Lock Screen's presses, run on the process the app runs a Live Activity intent in.
extension BackgroundDictationHarness {
    /// A press with rows of its own. The guard against a double tap needs one press for both taps.
    var chips: LockScreenPress {
        LockScreenPress(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivity,
            rows: LockScreenRows(),
            signIn: signIn,
            clock: clock
        )
    }

    /// What a chip the Lock Screen drew for `setID` hands back.
    func identity(
        of setID: ActiveSetID = firstSet,
        weight: Weight = .pounds(235),
        blockTab: String = "Block 27"
    ) -> String {
        LoggableSetIdentity(
            session: SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: 1, day: 1)),
            setID: setID,
            weight: weight
        ).storageValue
    }

    /// Presses an RPE Chip after `reps`.
    func press(
        _ identity: String,
        reps: Int = 5,
        rpe: String = "7",
        on chips: LockScreenPress? = nil
    ) async -> LockScreenPress.Outcome {
        let chips = chips ?? self.chips
        return await settled { await chips.logSet(setIdentity: identity, reps: reps, rpe: rpe) }
    }

    /// Presses a control that turns the card to `face`.
    func turn(to face: LockScreenFace, pressing identity: String?, on chips: LockScreenPress? = nil) async -> LockScreenPress.Outcome {
        let chips = chips ?? self.chips
        return await settled { await chips.turn(to: face, pressing: identity) }
    }

    /// Runs a press to its end, letting the hold of a readback over the rest run out.
    private func settled(_ press: @escaping @MainActor () async -> LockScreenPress.Outcome) async -> LockScreenPress.Outcome {
        let readbacks = liveActivity.shown.count
        var outcome: LockScreenPress.Outcome?
        let run = Task { outcome = await press() }
        await waitUntil({ outcome != nil || liveActivity.shown.count > readbacks }, orRecord: "The press neither ended nor read back")
        if outcome == nil, liveActivity.restContent != nil {
            let hold = LockScreenPress.readbackHold
            await clock.waitUntilSleeping(until: clock.now + hold, orRecord: "The readback never held")
            clock.advance(by: hold)
        }
        await run.value
        return outcome ?? .notLogged(.unreadable)
    }

    /// The rest the Lock Screen card rides, as the stage starts it once the previous Set logs.
    func restRunning() throws {
        let session = try #require(app.workout.currentSession)
        let active = try #require(focus.activeSet(in: session))
        focus.cardShows(SetLogDraft(weight: .pounds(235), reps: nil, rpe: nil), for: active.setID)
        liveActivity.restContent = LiveActivityRestContentBuilder.content(
            showing: active,
            in: session,
            reading: LoggablePressSource(focus: focus, history: app.lastPerformed.snapshot),
            restStartDate: clock.date,
            restEndDate: clock.date + 120
        )
    }

    /// The face the Lock Screen card is on; nil with no card up.
    var face: LockScreenFace? {
        liveActivity.restContent?.face
    }
}
