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

    /// Presses an RPE Chip after `reps` and lets the readback's hold run out.
    func press(
        _ identity: String,
        reps: Int = 5,
        rpe: String = "7",
        on chips: LockScreenPress? = nil
    ) async -> LockScreenPress.Outcome {
        let chips = chips ?? self.chips
        let run = Task { await chips.logSet(setIdentity: identity, reps: reps, rpe: rpe) }
        let shown = liveActivity.shown.count + liveActivity.noSets.count
        await waitUntil({ liveActivity.shown.count + liveActivity.noSets.count > shown }, orRecord: "It never read back")
        if liveActivity.restContent != nil {
            let hold = LockScreenPress.readbackHold
            await clock.waitUntilSleeping(until: clock.now + hold, orRecord: "The readback never held")
            clock.advance(by: hold)
        }
        return await run.value
    }

    /// Presses a Reps Chip, and lets a readback's hold run out when the press refused.
    func chooseReps(_ identity: String, reps: Int?, on chips: LockScreenPress? = nil) async -> LockScreenPress.Outcome {
        let chips = chips ?? self.chips
        let run = Task { await chips.chooseReps(setIdentity: identity, reps: reps) }
        let shown = liveActivity.shown.count + liveActivity.noSets.count
        let refreshed = liveActivity.refreshes.count
        await waitUntil(
            { liveActivity.shown.count + liveActivity.noSets.count > shown || liveActivity.refreshes.count > refreshed },
            orRecord: "The row never turned and nothing read back"
        )
        if liveActivity.shown.count + liveActivity.noSets.count > shown, liveActivity.restContent != nil {
            let hold = LockScreenPress.readbackHold
            await clock.waitUntilSleeping(until: clock.now + hold, orRecord: "The readback never held")
            clock.advance(by: hold)
        }
        return await run.value
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

    /// The Reps the card's row has chosen, nil while it offers Reps.
    var chosenReps: Int?? {
        guard case .ready(let offer) = liveActivity.restContent?.press else { return nil }
        return .some(offer.chosenReps)
    }
}
