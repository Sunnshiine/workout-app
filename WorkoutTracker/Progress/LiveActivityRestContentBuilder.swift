import Foundation

struct LiveActivityProductionEvent: Equatable, Sendable {
    enum Source: CaseIterable, Equatable, Sendable {
        case userSetLog
        case syncReload
        case sheetDerivedLoggedState
        case editSetLog
        case skipSet
        case deleteSetLog
        case appLaunchRestoration
        case settings
        case developerTools
        case nonCurrentSessionBrowsing
    }

    enum Outcome: Equatable, Sendable {
        case success
        case failure
    }

    enum SessionScope: Equatable, Sendable {
        case currentSession
        case nonCurrentSession
    }

    let source: Source
    let outcome: Outcome
    let sessionScope: SessionScope
}

enum LiveActivityCreationPolicy {
    static func shouldCreateOrUpdate(for event: LiveActivityProductionEvent) -> Bool {
        event.source == .userSetLog
            && event.outcome == .success
            && event.sessionScope == .currentSession
    }
}

enum LiveActivityRestContentVariant: Equatable, Sendable {
    case restTimerSetsLeft
}

struct LiveActivityRestContent: Equatable, Sendable {
    let exerciseName: String
    let prescribedReps: String
    let prescribedLoad: String
    let weightValue: String
    let weightUnit: String
    let setsDone: Int
    let setsTotal: Int
    let variant: LiveActivityRestContentVariant
    let restStartDate: Date
    let restEndDate: Date

    var setsLeft: Int {
        max(setsTotal - setsDone, 0)
    }

    var setsLeftText: String {
        setsLeft == 1 ? "1 set left" : "\(setsLeft) sets left"
    }
}

@MainActor
enum LiveActivityRestContentBuilder {
    static func content(
        afterLogging loggedSet: ExerciseSet,
        in session: Session,
        supersetState: SupersetState? = nil,
        restStartDate: Date,
        restEndDate: Date
    ) -> LiveActivityRestContent? {
        guard let target = targetSet(afterLogging: loggedSet, in: session, supersetState: supersetState) else {
            return nil
        }

        let sets = sortedSets(in: target.exercise)
        let pendingCount = sets.filter { $0.state == .pending }.count
        let totalCount = sets.count
        return LiveActivityRestContent(
            exerciseName: target.exercise.name,
            prescribedReps: target.set.prescribedReps,
            prescribedLoad: target.set.prescribedLoad,
            weightValue: "",
            weightUnit: "lbs",
            setsDone: max(totalCount - pendingCount, 0),
            setsTotal: totalCount,
            variant: .restTimerSetsLeft,
            restStartDate: restStartDate,
            restEndDate: restEndDate
        )
    }

    private static func targetSet(
        afterLogging loggedSet: ExerciseSet,
        in session: Session,
        supersetState: SupersetState?
    ) -> (exercise: Exercise, set: ExerciseSet)? {
        if let supersetSetID = supersetState?.nextSetID(after: loggedSet, in: session),
           let target = set(for: supersetSetID, in: session) {
            return target
        }

        if let sessionTarget = nextPendingSet(after: loggedSet, in: session) {
            return sessionTarget
        }

        return openExerciseFallback(for: session)
    }

    private static func nextPendingSet(
        after loggedSet: ExerciseSet,
        in session: Session
    ) -> (exercise: Exercise, set: ExerciseSet)? {
        guard let loggedSetID = ActiveSetFocusManager.id(for: loggedSet) else {
            return firstPendingSet(in: session)
        }

        let orderedSets = orderedSets(in: session)
        return
            orderedSets
            .drop { pair in
                ActiveSetID(exerciseOrder: pair.exercise.order, setIndex: pair.set.index) != loggedSetID
            }
            .dropFirst()
            .first { $0.set.state == .pending }
            ?? orderedSets.first { $0.set.state == .pending }
    }

    private static func openExerciseFallback(for session: Session) -> (exercise: Exercise, set: ExerciseSet)? {
        currentWeekSessions(for: session)
            .filter { $0.dayNumber < session.dayNumber }
            .sorted { $0.dayNumber < $1.dayNumber }
            .lazy
            .flatMap(orderedSets(in:))
            .first { $0.set.state == .pending }
    }

    private static func set(
        for setID: ActiveSetID,
        in session: Session
    ) -> (exercise: Exercise, set: ExerciseSet)? {
        orderedSets(in: session).first { pair in
            ActiveSetID(exerciseOrder: pair.exercise.order, setIndex: pair.set.index) == setID
        }
    }

    private static func orderedSets(in session: Session) -> [(exercise: Exercise, set: ExerciseSet)] {
        session.exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                sortedSets(in: exercise).map { (exercise, $0) }
            }
    }

    private static func sortedSets(in exercise: Exercise) -> [ExerciseSet] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    private static func firstPendingSet(in session: Session) -> (exercise: Exercise, set: ExerciseSet)? {
        orderedSets(in: session).first { $0.set.state == .pending }
    }

    private static func currentWeekSessions(for session: Session) -> [Session] {
        guard let week = session.week, !week.sessions.isEmpty else {
            return [session]
        }
        return week.sessions
    }
}
