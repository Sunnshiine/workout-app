import Foundation

enum BlockBuilder {
    static func makeBlock(from p: ParsedBlockModel) -> Block {
        let block = Block(tabName: p.tabName, squatTM: p.squatTM, benchTM: p.benchTM, deadliftTM: p.deadliftTM)
        block.weeks = p.weeks.map { pw in
            let week = Week(number: pw.number)
            week.sessions = pw.days.map { pd in
                let session = Session(dayNumber: pd.dayNumber, date: pd.date)
                session.exercises = pd.exercises.enumerated().map { (i, pe) in
                    let ex = Exercise(
                        name: pe.name,
                        baseName: pe.baseName,
                        cadence: pe.cadence,
                        coachNote: pe.coachNote,
                        legacyLog: pe.legacyLog,
                        order: i
                    )
                    ex.sets = pe.sets.map {
                        let set = ExerciseSet(
                            index: $0.index,
                            prescribedReps: $0.prescribedReps,
                            prescribedLoad: $0.prescribedLoad,
                            percentOneRM: $0.percentOneRM,
                            state: $0.state
                        )
                        set.setLog = $0.setLog
                        return set
                    }
                    return ex
                }
                return session
            }
            return week
        }
        return block
    }
}
