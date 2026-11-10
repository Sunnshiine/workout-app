import Foundation

extension WorkoutActivityAttributes.ContentState {
    init(
        restContent: LiveActivityRestContent,
        dictation: LiveActivityDictation?,
        appearance: LiveActivityAppearance = .dark
    ) {
        self.init(restContent: restContent, dictation: dictation, readbackStaysOffTheCard: nil, appearance: appearance)
    }

    /// The rest a Set logged from the Lock Screen card began: the card on its face, and `readback`
    /// on the island alone.
    init(restContent: LiveActivityRestContent, islandReading readback: LiveActivityDictation) {
        self.init(restContent: restContent, dictation: readback, readbackStaysOffTheCard: true, appearance: .dark)
    }

    /// `card` in this content's place, still under a readback the island alone reads.
    func redrawn(as card: LiveActivityRestContent) -> WorkoutActivityAttributes.ContentState {
        guard readbackStaysOffTheCard == true, let dictation else {
            return WorkoutActivityAttributes.ContentState(restContent: card, dictation: nil)
        }
        return WorkoutActivityAttributes.ContentState(restContent: card, islandReading: dictation)
    }

    private init(
        restContent: LiveActivityRestContent,
        dictation: LiveActivityDictation?,
        readbackStaysOffTheCard: Bool?,
        appearance: LiveActivityAppearance
    ) {
        self.init(
            exerciseName: restContent.exerciseName,
            prescribedReps: restContent.prescribedReps,
            prescribedLoad: restContent.prescribedLoad,
            weightValue: restContent.weightValue,
            weightUnit: restContent.weightUnit,
            setsDone: restContent.setsDone,
            setsTotal: restContent.setsTotal,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: restContent.restStartDate,
            restEndDate: restContent.restEndDate,
            dictation: dictation,
            readbackStaysOffTheCard: readbackStaysOffTheCard,
            loggablePress: LoggablePress(restContent.press),
            cardFace: LockScreenCardFace(restContent.face),
            cardTurn: LockScreenCardTurn(restContent.turn),
            cardStats: restContent.stats.map(LockScreenCardStat.init),
            cadence: restContent.cadence,
            coachNote: restContent.coachNote,
            start: restContent.start.map(LockScreenStartOffer.init),
            pendingWrites: restContent.pendingWrites
        )
    }

    /// A headless Dictation over the Set it listened for, with no rest running.
    init(
        setContent: LiveActivitySetContent,
        dictation: LiveActivityDictation,
        appearance: LiveActivityAppearance = .dark
    ) {
        self.init(
            exerciseName: setContent.exerciseName,
            prescribedReps: setContent.prescribedReps,
            prescribedLoad: setContent.prescribedLoad,
            weightValue: "",
            weightUnit: "lbs",
            setsDone: setContent.setsDone,
            setsTotal: setContent.setsTotal,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: nil,
            restEndDate: nil,
            dictation: dictation,
            readbackStaysOffTheCard: nil,
            loggablePress: .needsApp,
            cardFace: .rest,
            cardTurn: nil,
            cardStats: [],
            cadence: nil,
            coachNote: nil,
            start: nil,
            pendingWrites: setContent.pendingWrites
        )
    }

    /// The Set a Lock Screen press logged with no rest to follow: its Set Log's numbers on the
    /// card with nothing to press, and `readback` on the island alone.
    init(
        loggedSet: LiveActivityLoggedSetContent,
        islandReading readback: LiveActivityDictation,
        appearance: LiveActivityAppearance = .dark
    ) {
        self.init(
            exerciseName: loggedSet.set.exerciseName,
            prescribedReps: loggedSet.set.prescribedReps,
            prescribedLoad: loggedSet.set.prescribedLoad,
            weightValue: "",
            weightUnit: "lbs",
            setsDone: loggedSet.set.setsDone,
            setsTotal: loggedSet.set.setsTotal,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: nil,
            restEndDate: nil,
            dictation: readback,
            readbackStaysOffTheCard: true,
            loggablePress: .settled,
            cardFace: .rest,
            cardTurn: nil,
            cardStats: loggedSet.stats.map(LockScreenCardStat.init),
            cadence: nil,
            coachNote: nil,
            start: nil,
            pendingWrites: loggedSet.set.pendingWrites
        )
    }

    /// A readback about the Session with no rest running, so it carries no Set.
    init(noSetToLog dictation: LiveActivityDictation, appearance: LiveActivityAppearance = .dark) {
        self.init(
            exerciseName: "",
            prescribedReps: "",
            prescribedLoad: "",
            weightValue: "",
            weightUnit: "lbs",
            setsDone: 0,
            setsTotal: 0,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: nil,
            restEndDate: nil,
            dictation: dictation,
            readbackStaysOffTheCard: nil,
            loggablePress: .needsApp,
            cardFace: .rest,
            cardTurn: nil,
            cardStats: [],
            cadence: nil,
            coachNote: nil,
            start: nil,
            pendingWrites: 0
        )
    }
}

extension LoggablePress {
    init(_ press: LoggablePressContent) {
        switch press {
        case .ready(let offer):
            self = .ready(
                Offer(
                    repChoices: offer.repChoices,
                    prescribedReps: offer.prescribedReps,
                    rpeChoices: offer.rpeChoices,
                    prescribedRPE: offer.prescribedRPE,
                    setIdentity: offer.setIdentity
                )
            )
        case .needsApp:
            self = .needsApp
        }
    }
}

extension LoggablePressContent {
    /// Nil for a settled Set, whose card runs no rest and offers nothing.
    init?(_ press: LoggablePress) {
        switch press {
        case .ready(let offer):
            self = .ready(
                LockScreenOffer(
                    repChoices: offer.repChoices,
                    prescribedReps: offer.prescribedReps,
                    rpeChoices: offer.rpeChoices,
                    prescribedRPE: offer.prescribedRPE,
                    setIdentity: offer.setIdentity
                )
            )
        case .needsApp:
            self = .needsApp
        case .settled:
            return nil
        }
    }
}

extension LockScreenCardTurn {
    init(_ turn: LockScreenTurn) {
        switch turn {
        case .forward: self = .forward
        case .back: self = .back
        }
    }
}

extension LockScreenCardFace {
    init(_ face: LockScreenFace) {
        switch face {
        case .rest: self = .rest
        case .coachNote: self = .coachNote
        case .reps: self = .reps
        case .rpe(let reps): self = .rpe(reps: reps)
        }
    }
}

extension LockScreenFace {
    init(_ face: LockScreenCardFace) {
        switch face {
        case .rest: self = .rest
        case .coachNote: self = .coachNote
        case .reps: self = .reps
        case .rpe(let reps): self = .rpe(reps: reps)
        }
    }
}

extension LockScreenCardStat {
    init(_ stat: LockScreenStat) {
        self.init(label: stat.label, value: stat.value, spoken: stat.spoken, isMissing: stat.isMissing)
    }
}

extension LockScreenStat {
    init(_ stat: LockScreenCardStat) {
        self.init(label: stat.label, value: stat.value, spoken: stat.spoken, isMissing: stat.isMissing)
    }
}

extension LockScreenStartOffer {
    init(_ start: LockScreenStart) {
        self.init(label: start.effort.controlLabel, spokenLabel: start.effort.spokenLabel, url: start.request.url)
    }
}

extension LiveActivityDictation {
    init(_ noSet: LiveActivityNoSetReadback) {
        switch noSet {
        case .noSetLeft: self = .noSetLeft
        case .noCurrentSession: self = .noCurrentSession
        }
    }

    init(_ readback: LiveActivityDictationContent.Readback) {
        switch readback {
        case .listening: self = .listening
        case .logged(let setLog, let set): self = .logged(setLog, to: LiveActivityWrittenSet(set))
        case .skipped(let set): self = .skipped(LiveActivityWrittenSet(set))
        case .notLogged(let reason): self = .notLogged(reason)
        case .settled(let setLog, let set): self = .settled(setLog: setLog, LiveActivityWrittenSet(set))
        }
    }
}

extension LiveActivityRestContent {
    /// The rest a running activity shows, read back off it, leading to no Set this process knows.
    init?(leftRunning state: WorkoutActivityAttributes.ContentState) {
        guard let restStartDate = state.restStartDate, let restEndDate = state.restEndDate,
            let press = LoggablePressContent(state.loggablePress)
        else { return nil }
        let rest = LiveActivityRestContent(
            exerciseName: state.exerciseName,
            prescribedReps: state.prescribedReps,
            prescribedLoad: state.prescribedLoad,
            weightValue: state.weightValue,
            weightUnit: state.weightUnit,
            setsDone: state.setsDone,
            setsTotal: state.setsTotal,
            variant: .restTimerSetsLeft,
            restStartDate: restStartDate,
            restEndDate: restEndDate,
            press: press,
            stats: state.stats.map(LockScreenStat.init),
            cadence: state.cadence,
            coachNote: state.coachNote,
            start: nil,
            target: nil
        )
        self = rest.turned(to: LockScreenFace(state.face))
        pendingWrites = state.pendingWrites
    }
}

extension LiveActivityWrittenSet {
    init(_ set: LiveActivityDictationContent.WrittenSet) {
        self.init(exerciseName: set.exerciseName, setOrdinal: set.setOrdinal, setsTotal: set.setsTotal)
    }
}
