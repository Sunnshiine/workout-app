import Foundation

extension SessionCoordinator {
    /// Nil keeps the mic off the card: no transcriber, or a Set the card neither logs nor reviews.
    func cardDictation(for slot: SetCardSlot) -> SetCardDictation? {
        guard let dictation, spokenWriteMode(for: slot.set) == slot.mode.cardMode, let setID = Self.activeSetID(for: slot.set) else {
            return nil
        }
        return SetCardDictation(dictation.state, for: setID)
    }

    /// How the card writes a Spoken Set for `set`: as a log of a Pending Set, or as a save over the
    /// logged Set under review. Nil for any other Set, which takes nothing said.
    private func spokenWriteMode(for set: ExerciseSet) -> SetCardMode? {
        guard let setID = Self.activeSetID(for: set) else { return nil }
        if set.isPending { return .logging }
        if set.state == .logged, focusManager.expandedLoggedSetID == setID { return .reviewingLogged }
        return nil
    }

    func startDictation(for set: ExerciseSet) {
        guard let dictation, let setID = Self.activeSetID(for: set), let pressed = onStageID(of: set),
            let mode = spokenWriteMode(for: set), dictation.start(for: setID)
        else { return }
        dictatingSet = pressed
        dictatingMode = mode
    }

    /// The card reports what it shows for `set` as the athlete changes it, which fills what a
    /// Spoken Set leaves unsaid, from the card's mic or a press with the phone locked alike.
    func cardShows(_ draft: SetLogDraft, for set: ExerciseSet) {
        guard let setID = Self.activeSetID(for: set) else { return }
        focusManager.cardShows(draft, for: setID)
    }

    /// Writes what the athlete said through the same paths as the card's Log and skip, with what
    /// they left unsaid read from what `set`'s card shows. A press begun on another Session or for
    /// another Set writes nothing, as `write(_:heardFor:in:)` says of a Set the card no longer
    /// writes as the press began. A sync that lands while the transcript is read leaves the write
    /// to the Session parsed again, and to nothing when it put another Set in the pressed Set's place.
    func finishDictation(of set: ExerciseSet) async -> SetDictation.Outcome? {
        guard let dictation, let setID = dictation.state.pressSetID else { return nil }
        guard let session = sessionOfPress(for: setID, releasedOn: set), let coordinate = session.placement.coordinate else {
            await dictation.cancel()
            return nil
        }
        let outcome = await dictation.finish(for: setID, in: spokenSetContext(for: set))
        return write(outcome, heardFor: setID, in: currentSession(at: coordinate) ?? session)
    }

    func spokenSetContext(for set: ExerciseSet) -> SpokenSetContext {
        SpokenSetContext(for: set, shownBy: focusManager, history: wiring.history())
    }

    /// The Session `setID`'s press began in, while it is on stage and `set` is that Set in it.
    private func sessionOfPress(for setID: ActiveSetID, releasedOn set: ExerciseSet) -> Session? {
        guard let session = set.exercise?.session, isOnStage(session), sessionCoordinate == dictatingSet?.session,
            Self.activeSetID(for: set) == setID
        else { return nil }
        return session
    }

    func pendingSet(at setID: ActiveSetID, in session: Session) -> ExerciseSet? {
        guard isOnStage(session), let set = session.set(at: setID), set.isPending else { return nil }
        return set
    }

    /// The card writes what was said as it would a tap, in the mode the press began in. A Set the
    /// card no longer writes that way once the transcript is in, as one logged by hand during a
    /// press for its log, takes nothing, and neither does a write the mode refuses, as a skip said
    /// over a review: its outcome goes, so the card answers no write it did not make.
    func write(_ outcome: SetDictation.Outcome?, heardFor setID: ActiveSetID, in session: Session) -> SetDictation.Outcome? {
        guard let outcome else { return nil }
        guard let (set, mode) = spokenWriteTarget(at: setID, in: session) else {
            dictation?.dismiss()
            return nil
        }
        guard let cardWrite = CardWrite(outcome) else { return outcome }
        guard write(cardWrite, to: set, as: mode, from: .speech) else {
            dictation?.dismiss()
            return nil
        }
        return outcome
    }

    /// The Set at `setID` in `session` and the mode the press began in, while it is still the Set the
    /// press began on, on stage, and the card still writes it that way. A sync that put another
    /// Exercise's Set in its place leaves the press nothing to write, since `setID` names a place,
    /// not a Set.
    private func spokenWriteTarget(at setID: ActiveSetID, in session: Session) -> (ExerciseSet, SetCardMode)? {
        guard let set = session.set(at: setID), let pressed = dictatingSet, onStageID(of: set) == pressed,
            let mode = dictatingMode, spokenWriteMode(for: set) == mode
        else { return nil }
        return (set, mode)
    }

    /// Stops the press for `set` whose control left the screen, writing nothing. A control that
    /// leaves while another card's press runs, as an outgoing card's can after the incoming one
    /// starts listening, stops nothing.
    func cancelDictation(of set: ExerciseSet) async {
        guard let dictation, let setID = dictation.state.pressSetID, Self.activeSetID(for: set) == setID,
            let coordinate = set.exercise?.session?.placement.coordinate, coordinate == dictatingSet?.session
        else { return }
        await dictation.cancel()
    }

    func dismissDictation() {
        dictation?.dismiss()
    }
}

@MainActor
extension Session {
    fileprivate func set(at setID: ActiveSetID) -> ExerciseSet? {
        exercises.first { $0.order == setID.exerciseOrder }?.sets.first { $0.index == setID.setIndex }
    }
}
