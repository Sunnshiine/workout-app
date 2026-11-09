import Foundation

/// What a request from outside the app does next.
enum AppEntryRoute: Equatable {
    /// The stage has no Session yet, as on a cold launch.
    case wait
    case showCurrentSession
    /// The card shows a logged Set in place of the active one.
    case uncoverActiveSet
    /// The card for this Set takes the request when it shows.
    case cardTakes(ActiveSetID)
    /// Nothing to answer, so the request ends with the stage where it is.
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
        case .showCurrentSession, .uncoverActiveSet, .cardTakes:
            entry.closeCovers()
            moveStage(toward: route)
        }
    }

    /// The card takes a `.cardTakes` request itself once it shows, so only the other routes move it.
    private func moveStage(toward route: AppEntryRoute) {
        switch route {
        case .showCurrentSession:
            wiring.navigation.showCurrent()
        case .uncoverActiveSet:
            endSpokenWriteHold()
            perform(nil) { focusManager.collapseLoggedSetReview() }
        case .wait, .drop, .cardTakes:
            break
        }
    }

    /// True while a request waits for `slot`'s card to listen for its Set.
    func startsHandsFree(_ slot: SetCardSlot) -> Bool {
        slot.mode == .logging && setTaking(.dictation, at: slot.set) != nil
    }

    /// The Set of `set`'s card while a request of `kind` waits for that card to take it.
    func setTaking(_ kind: AppEntryRequest.Kind, at set: ExerciseSet) -> ActiveSetID? {
        guard wiring.entry.pending?.kind == kind, case .cardTakes(let setID) = entryRoute, Self.activeSetID(for: set) == setID else {
            return nil
        }
        return setID
    }

    /// Takes the waiting request and listens for `set` until the athlete stops talking, writing
    /// what was said as a release of the mic would, with what was left unsaid read from what the
    /// card shows when listening ends. A sync that lands while it listens leaves the write to the
    /// Session parsed again, and to nothing when it put another Set in the listened Set's place.
    func listenHandsFree(to set: ExerciseSet) async -> SetDictation.Outcome? {
        guard let dictation, let setID = setTaking(.dictation, at: set), let listened = onStageID(of: set) else { return nil }
        _ = wiring.entry.take()
        countdown.cancel()
        dictatingSet = listened
        dictatingMode = .logging
        let outcome = await dictation.listenUntilQuiet(for: setID, on: .card) { spokenSetContext(for: set) }
        guard let session = currentSession(at: listened.session) else {
            dictation.dismiss()
            return nil
        }
        return write(outcome, heardFor: setID, in: session)
    }

    /// Nil while no request waits.
    var entryRoute: AppEntryRoute? {
        guard let request = wiring.entry.pending else { return nil }
        guard let sessionCoordinate else { return .wait }
        guard canAnswer(request) else { return .drop }
        guard let session = currentSession(at: sessionCoordinate) else { return .showCurrentSession }
        return entryRoute(onLiveEdgeOf: session, for: request)
    }

    /// A Start names its Session, which must still be the Current Session.
    private func canAnswer(_ request: AppEntryRequest) -> Bool {
        switch request {
        case .dictateCurrentSet: micIsFreeForAPendingSet
        case .startTimedEffort(let owner): wiring.navigation.currentSession?.placement.coordinate == owner.session
        }
    }

    /// True while the mic is idle and the Current Session still has a Pending Set to log.
    private var micIsFreeForAPendingSet: Bool {
        guard let dictation, dictation.state.pressSetID == nil, let current = wiring.navigation.currentSession else { return false }
        return SessionSetOrder.firstPendingSet(in: current) != nil
    }

    /// A Start for another Set than the card's ends here, so a card the Lock Screen drew before the
    /// stage moved on never starts the count for the wrong Set.
    private func entryRoute(onLiveEdgeOf session: Session, for request: AppEntryRequest) -> AppEntryRoute {
        switch focusManager.visualFocusOwner {
        case .loggedSetReview, .heldAfterSpokenWrite:
            return .uncoverActiveSet
        case .activeSet(let setID) where pendingSet(at: setID, in: session) != nil && request.isAnswered(at: setID):
            return .cardTakes(setID)
        case .activeSet, nil:
            return .drop
        }
    }
}

extension AppEntryRequest {
    fileprivate func isAnswered(at setID: ActiveSetID) -> Bool {
        switch self {
        case .dictateCurrentSet: true
        case .startTimedEffort(let owner): owner.set == setID
        }
    }
}
