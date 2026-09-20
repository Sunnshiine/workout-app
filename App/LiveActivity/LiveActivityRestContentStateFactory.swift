import Foundation

extension WorkoutActivityAttributes.ContentState {
    init(
        restContent: LiveActivityRestContent,
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
            restEndDate: restContent.restEndDate
        )
    }
}
