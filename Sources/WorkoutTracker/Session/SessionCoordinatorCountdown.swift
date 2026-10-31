import Foundation

/// The timed effort the Set card offers, and its Effort Countdown while one runs for the card's
/// Set.
struct SetCardCountdown: Equatable {
    let effort: TimedEffort
    let run: CountdownRun?
}

extension SessionCoordinator {
    var countdown: EffortCountdown { wiring.countdown }

    /// Nil keeps the control off the card: a Set the card does not log, or one with no timed
    /// effort. Every Pending Set of an Exercise whose Coach Note prescribes an Opening Hold
    /// offers it.
    func cardCountdown(for slot: SetCardSlot) -> SetCardCountdown? {
        guard slot.mode == .logging, slot.set.isPending, let effort = slot.set.timedEffort, let owner = countdownOwner(of: slot.set)
        else { return nil }
        return SetCardCountdown(effort: effort, run: countdown.run.flatMap { $0.owner == owner ? $0 : nil })
    }

    /// One tap starts the card's timed effort after the Lead-in. A rest still running is over,
    /// since the athlete is at the machine for the next Set.
    func startCountdown(for slot: SetCardSlot) {
        guard let card = cardCountdown(for: slot), card.run == nil, let owner = countdownOwner(of: slot.set) else { return }
        wiring.restTimer.dismiss()
        wiring.liveActivity.end()
        countdown.start(card.effort, for: owner)
    }

    func cancelCountdown() {
        countdown.cancel()
    }

    /// Ends the countdown once the card no longer shows its Set to log: focus moved, a review or a
    /// held Set covers it, or the stage left its Session. A sync's re-parse of the same Session
    /// keeps the Set where it was, and the countdown with it.
    func cancelCountdownOffItsSet() {
        guard let run = countdown.run, run.owner != shownCountdownOwner else { return }
        countdown.cancel()
    }

    /// The Set the card shows to log, as a countdown names it.
    private var shownCountdownOwner: CountdownRun.Owner? {
        guard let sessionCoordinate, case .activeSet(let setID) = focusManager.visualFocusOwner else { return nil }
        return CountdownRun.Owner(session: sessionCoordinate, set: setID)
    }

    private func countdownOwner(of set: ExerciseSet) -> CountdownRun.Owner? {
        guard let session = onStageID(of: set)?.session, let setID = Self.activeSetID(for: set) else { return nil }
        return CountdownRun.Owner(session: session, set: setID)
    }
}
