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
            dictation: dictation
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
            dictation: dictation
        )
    }
}

extension LiveActivityDictation {
    init(_ readback: LiveActivityDictationContent.Readback) {
        switch readback {
        case .listening: self = .listening
        case .logged(let setLog): self = .logged(setLog)
        case .skipped: self = .skipped
        case .notLogged(let reason): self = .notLogged(reason)
        }
    }
}
