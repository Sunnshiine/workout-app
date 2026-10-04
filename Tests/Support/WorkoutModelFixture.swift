@testable import WorkoutTracker

private let wholePointRPEs: [RPE] = [.seven, .eight, .nine, .ten]

@MainActor
func makeExercise(
    name: String = "Competition Squat",
    order: Int = 0,
    setStates: [SetState]
) -> Exercise {
    let exercise = Exercise(name: name, baseName: name, cadence: nil, coachNote: nil, order: order)
    exercise.sets = setStates.enumerated().map { index, state in
        let rpe = wholePointRPEs[min(index, wholePointRPEs.count - 1)]
        let set = ExerciseSet(
            index: index,
            prescribedReps: "5",
            prescribedLoad: "RPE \(rpe.label)",
            percentOneRM: nil,
            state: state
        )
        if state == .logged {
            set.setLog = SetLog(weight: .pounds(185 + Double(index * 10)), reps: 5, rpe: rpe)
        }
        return set
    }
    return exercise
}

@MainActor
func makeSession(
    at address: SessionAddress,
    setStates: [SetState],
    exerciseName: String = "Competition Squat"
) -> Session {
    let session = Session(dayNumber: address.day, date: nil)
    session.exercises = [
        makeExercise(name: exerciseName, setStates: setStates)
    ]

    let week = Week(number: address.week)
    week.sessions = [session]
    return session
}

@MainActor
func makeBlock(tabName: String = "Block 40", sessions: [Session]) -> Block {
    let block = Block(tabName: tabName)
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

@MainActor
func makeBenchPress(
    loads: [String],
    blockTab: String = "Block 27",
    at address: SessionAddress = SessionAddress(week: 1, day: 2),
    trainingMaxes: [MainLift: Double] = [:]
) -> Exercise {
    let block = Block(tabName: blockTab, trainingMaxes: trainingMaxes)
    let week = Week(number: address.week)
    week.block = block
    let session = Session(dayNumber: address.day, date: nil)
    session.week = week
    let exercise = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 0)
    exercise.session = session
    exercise.sets = loads.enumerated().map { index, load in
        ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: load, percentOneRM: nil, state: .pending)
    }
    return exercise
}
