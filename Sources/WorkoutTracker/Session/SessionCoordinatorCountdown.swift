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
        guard slot.mode == .logging, let effort = Self.offeredEffort(on: slot.set), let owner = countdownOwner(of: slot.set) else {
            return nil
        }
        return SetCardCountdown(effort: effort, run: countdown.run.flatMap { $0.owner == owner ? $0 : nil })
    }

    /// One tap starts the card's timed effort after the Lead-in. A rest still running is over,
    /// since the athlete is at the machine for the next Set.
    func startCountdown(for slot: SetCardSlot) {
        guard let card = cardCountdown(for: slot), card.run == nil, let owner = countdownOwner(of: slot.set) else { return }
        wiring.restTimer.dismiss()
        wiring.liveActivity.end()
        countdown.start(card.effort, for: owner) { [weak self] run in
            self?.cardStillOffers(run) ?? false
        }
    }

    func cancelCountdown() {
        countdown.cancel()
    }

    /// Ends the countdown once the card no longer offers it: focus moved, a review or a held Set
    /// covers it, the stage left its Session, its Set is no longer Pending, or a sync's re-parse
    /// changed its effort. A re-parse that keeps the Set Pending with the same effort keeps the
    /// countdown.
    func cancelCountdownOffItsSet() {
        guard let run = countdown.run, !cardStillOffers(run) else { return }
        countdown.cancel()
    }

    /// True while the card shows the run's Set to log, in the Session the athlete is viewing, and
    /// that Set still offers the run's effort.
    private func cardStillOffers(_ run: CountdownRun) -> Bool {
        guard run.owner == shownCountdownOwner, let session = wiring.navigation.viewedSession,
            session.placement.coordinate == run.owner.session,
            let set = SessionSetOrder.orderedSets(in: session).first(where: { $0.setID == run.owner.set })?.set
        else { return false }
        return Self.offeredEffort(on: set) == run.effort
    }

    /// A Pending Set's timed effort. A Set that is logged or skipped offers none.
    private static func offeredEffort(on set: ExerciseSet) -> TimedEffort? {
        set.isPending ? set.timedEffort : nil
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
