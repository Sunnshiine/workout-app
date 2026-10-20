import Foundation

/// What a request to say the Current Session's active Set does next.
enum SetDictationEntryRoute: Equatable {
    /// The stage has no Session yet, as on a cold launch.
    case wait
    case showCurrentSession
    /// The card shows a logged Set in place of the active one.
    case uncoverActiveSet
    /// The card for this Set takes the request when it shows.
    case listen(ActiveSetID)
    /// Nothing to listen for, so the request ends with the stage where it is.
    case drop
}

extension SessionCoordinator {
    /// Closes whatever covers the stage and moves it toward the Current Session's active Set for
    /// a waiting request, or ends a request there is nothing to listen for, leaving the stage as
    /// it is. Run when a request arrives and on every bind.
    func answerEntry() {
        guard let route = entryRoute else { return }
        let entry = wiring.entry
        switch route {
        case .wait:
            break
        case .drop:
            entry.discard()
        case .showCurrentSession, .uncoverActiveSet, .listen:
            entry.closeCovers()
            moveStage(toward: route)
        }
    }

    /// The card takes a `.listen` request itself once it shows, so only the other routes move it.
    private func moveStage(toward route: SetDictationEntryRoute) {
        switch route {
        case .showCurrentSession:
            wiring.navigation.showCurrent()
        case .uncoverActiveSet:
            endSpokenWriteHold()
            perform(nil) { focusManager.collapseLoggedSetReview() }
        case .wait, .drop, .listen:
            break
        }
    }

    /// True while a request waits for `slot`'s card to listen for its Set.
    func startsHandsFree(_ slot: SetCardSlot) -> Bool {
        guard slot.mode == .logging, case .listen(let setID) = entryRoute else { return false }
        return Self.activeSetID(for: slot.set) == setID
    }

    /// Takes the waiting request and listens for `set` until the athlete stops talking, writing
    /// what was said as a release of the mic would, with what was left unsaid read from what the
    /// card shows when listening ends.
    func listenHandsFree(to set: ExerciseSet) async -> SetDictation.Outcome? {
        guard let dictation, let session, case .listen(let setID) = entryRoute, Self.activeSetID(for: set) == setID else { return nil }
        _ = wiring.entry.take()
        dictatingSession = session
        let outcome = await dictation.listenUntilQuiet(for: setID) { spokenSetContext(for: set) }
        return write(outcome, heardFor: setID, in: session)
    }

    /// Nil while no request waits.
    private var entryRoute: SetDictationEntryRoute? {
        guard wiring.entry.pending != nil else { return nil }
        guard let session else { return .wait }
        guard micIsFreeForAPendingSet else { return .drop }
        guard wiring.navigation.liveEdge(for: session).isAtLiveEdge else { return .showCurrentSession }
        return entryRoute(onLiveEdgeOf: session)
    }

    /// True while the mic is idle and the Current Session still has a Pending Set to log.
    private var micIsFreeForAPendingSet: Bool {
        guard let dictation, dictation.state.listeningSetID == nil, let current = wiring.navigation.currentSession else { return false }
        return SessionSetOrder.firstPendingSet(in: current) != nil
    }

    private func entryRoute(onLiveEdgeOf session: Session) -> SetDictationEntryRoute {
        switch focusManager.visualFocusOwner {
        case .loggedSetReview, .heldAfterSpokenWrite:
            return .uncoverActiveSet
        case .activeSet(let setID) where pendingSet(at: setID, in: session) != nil:
            return .listen(setID)
        case .activeSet, nil:
            return .drop
        }
    }
}
