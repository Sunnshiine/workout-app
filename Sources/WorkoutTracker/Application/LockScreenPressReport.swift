import Foundation

/// What the Lock Screen offers for the Current Session's active Set, for a client with no Live Activity.
public struct LockScreenOfferReport: Encodable, Equatable, Sendable {
    public struct Offer: Encodable, Equatable, Sendable {
        public let repChoices: [Int]
        public let prescribedReps: [Int]
        public let rpeChoices: [String]
        public let prescribedRPE: String?
        public let setIdentity: String
    }

    /// Nil with no Pending Set left in the Current Session.
    public let set: SetAddress?
    public let exercise: String?
    /// The weight the card holds, as the Set Log writes it; nil when it holds none.
    public let weight: String?
    public let prescribedReps: String?
    public let prescribedLoad: String?
    /// The Cadence and the Coach Note on the card's one line.
    public let guidance: String?
    /// The timed effort the card's Start opens the app to count, as `10 s hold`.
    public let start: String?
    /// Nil when the card shows no chips.
    public let offer: Offer?
}

/// What one press did. `reason` says why when it logged nothing.
public struct RPEChipPressReport: Encodable, Equatable, Sendable {
    public enum Outcome: String, Encodable, Sendable {
        case logged, sameSetLog, notLogged
    }

    public let outcome: Outcome
    public let set: SetAddress?
    public let setLog: String?
    public let reason: String?
    public let pendingWriteCount: Int
}

extension WorkoutApplication {
    /// The card the Lock Screen draws, from a card fresh in this process: what no client has edited.
    public func lockScreenOffer() -> LockScreenOfferReport {
        let session = workout.currentSession
        let focus = ActiveSetFocusManager(session: session)
        guard let session, let active = focus.activeSet(in: session) else {
            return LockScreenOfferReport(
                set: nil,
                exercise: nil,
                weight: nil,
                prescribedReps: nil,
                prescribedLoad: nil,
                guidance: nil,
                start: nil,
                offer: nil
            )
        }
        let card = LiveActivityRestContentBuilder.content(
            showing: active,
            in: session,
            reading: LoggablePressSource(focus: focus, history: lastPerformed.snapshot),
            restStartDate: .distantPast,
            restEndDate: .distantPast
        )
        return LockScreenOfferReport(
            set: SetAddress(active.setID, in: session),
            exercise: card.exerciseName,
            weight: card.weightValue.isEmpty ? nil : card.weightValue,
            prescribedReps: card.prescribedReps,
            prescribedLoad: card.prescribedLoad,
            guidance: card.guidance,
            start: card.start?.effort.controlLabel,
            offer: LockScreenOfferReport.Offer(card.press)
        )
    }

    /// `LockScreenPress`'s decision and write for an RPE Chip pressed after a Reps Chip. The rest,
    /// the focus, and the Live Activity it goes on to move live in the app's process, so a client
    /// with no stage has none to move.
    public func pressRPEChip(setIdentity: String, reps: Int, rpe: String) throws -> RPEChipPressReport {
        let session = workout.currentSession
        let focus = ActiveSetFocusManager(session: session)
        switch LockScreenPress.decision(setIdentity: setIdentity, reps: reps, rpe: rpe, session: session, focus: focus) {
        case .write(let setLog, let position, let session):
            try workout.log(position.set, as: setLog)
            return RPEChipPressReport(
                outcome: .logged,
                set: SetAddress(position.setID, in: session),
                setLog: setLog.formatted,
                reason: nil,
                pendingWriteCount: try sync.fetchPendingWriteRecords().count
            )
        case .sameSetLog(let setID):
            return RPEChipPressReport(
                outcome: .sameSetLog,
                set: session.flatMap { SetAddress(setID, in: $0) },
                setLog: nil,
                reason: nil,
                pendingWriteCount: try sync.fetchPendingWriteRecords().count
            )
        case .refuse(let why):
            return RPEChipPressReport(
                outcome: .notLogged,
                set: nil,
                setLog: nil,
                reason: why.caption,
                pendingWriteCount: try sync.fetchPendingWriteRecords().count
            )
        }
    }
}

extension LockScreenOfferReport.Offer {
    fileprivate init?(_ press: LoggablePressContent) {
        guard case .ready(let offer) = press else { return nil }
        self.init(
            repChoices: offer.repChoices,
            prescribedReps: offer.prescribedReps,
            rpeChoices: offer.rpeChoices,
            prescribedRPE: offer.prescribedRPE,
            setIdentity: offer.setIdentity
        )
    }
}

extension SetAddress {
    fileprivate init?(_ setID: ActiveSetID, in session: Session) {
        guard let address = session.placement.coordinate?.address else { return nil }
        self.init(exercise: ExerciseAddress(session: address, order: setID.exerciseOrder), index: setID.setIndex)
    }
}
