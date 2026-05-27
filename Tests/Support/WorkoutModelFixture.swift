@testable import WorkoutTracker

@MainActor
func makeExercise(
    name: String = "Competition Squat",
    order: Int = 0,
    setStates: [SetState]
) -> Exercise {
    let exercise = Exercise(name: name, baseName: name, cadence: nil, coachNote: nil, order: order)
    exercise.sets = setStates.enumerated().map { index, state in
        let set = ExerciseSet(
            index: index,
            prescribedReps: "5",
            prescribedLoad: "RPE \(7 + index)",
            percentOneRM: nil,
            state: state
        )
        if state == .logged {
            set.setLog = SetLog(weight: .pounds(185 + Double(index * 10)), reps: 5, rpe: Double(7 + index))
        }
        return set
    }
    return exercise
}

@MainActor
func makeSession(
    weekNumber: Int,
    dayNumber: Int,
    setStates: [SetState],
    exerciseName: String = "Competition Squat"
) -> Session {
    let session = Session(dayNumber: dayNumber, date: nil)
    session.exercises = [
        makeExercise(name: exerciseName, setStates: setStates)
    ]

    let week = Week(number: weekNumber)
    week.sessions = [session]
    return session
}

@MainActor
func makeBlock(tabName: String = "Block 40", sessions: [Session]) -> Block {
    let block = Block(tabName: tabName, squatTM: nil, benchTM: nil, deadliftTM: nil)
    let weeks = Dictionary(grouping: sessions) { session in
        session.week?.number ?? 0
    }
    block.weeks = weeks.keys.sorted().map { weekNumber in
        let week = Week(number: weekNumber)
        week.sessions = weeks[weekNumber]?.sorted { $0.dayNumber < $1.dayNumber } ?? []
        return week
    }
    return block
}
