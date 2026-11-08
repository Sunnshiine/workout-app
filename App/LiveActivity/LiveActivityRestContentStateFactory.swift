import Foundation

extension WorkoutActivityAttributes.ContentState {
    init(
        restContent: LiveActivityRestContent,
        dictation: LiveActivityDictation?,
        appearance: LiveActivityAppearance = .dark
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
            loggablePress: LoggablePress(restContent.press),
            guidance: restContent.guidance,
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
            loggablePress: .needsApp,
            guidance: nil,
            start: nil,
            pendingWrites: setContent.pendingWrites
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
            loggablePress: .needsApp,
            guidance: nil,
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
                    setIdentity: offer.setIdentity,
                    chosenReps: offer.chosenReps
                )
            )
        case .needsApp:
            self = .needsApp
        }
    }
}

extension LoggablePressContent {
    init(_ press: LoggablePress) {
        switch press {
        case .ready(let offer):
            self = .ready(
                LockScreenOffer(
                    repChoices: offer.repChoices,
                    prescribedReps: offer.prescribedReps,
                    rpeChoices: offer.rpeChoices,
                    prescribedRPE: offer.prescribedRPE,
                    setIdentity: offer.setIdentity,
                    chosenReps: offer.chosenReps
                )
            )
        case .needsApp:
            self = .needsApp
        }
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
        case .noSetLeft(let session): self = .noSetLeft(session: session)
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
        guard let restStartDate = state.restStartDate, let restEndDate = state.restEndDate else { return nil }
        self.init(
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
            press: LoggablePressContent(state.loggablePress),
            guidance: state.guidance,
            start: nil,
            target: nil
        )
        pendingWrites = state.pendingWrites
    }
}

extension LiveActivityWrittenSet {
    init(_ set: LiveActivityDictationContent.WrittenSet) {
        self.init(exerciseName: set.exerciseName, setOrdinal: set.setOrdinal, setsTotal: set.setsTotal)
    }
}
