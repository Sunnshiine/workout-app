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

enum LiveActivityInvalidationEvent: Equatable, Sendable {
    case moveOn
    case sheetSwitch
    case signOut
    case restExpired
    case appBackgrounded
    case syncStateChanged
    case settingsOpened
    case developerToolsOpened
}

enum LiveActivityRestContentVariant: Equatable, Sendable {
    case restTimerSetsLeft
}

struct LiveActivitySessionIdentity: Equatable, Sendable {
    let blockTab: String?
    let weekNumber: Int?
    let dayNumber: Int
}

struct LiveActivityRestTarget: Equatable, Sendable {
    let session: LiveActivitySessionIdentity
    let setID: ActiveSetID
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
    var target: LiveActivityRestTarget?

    init(
        exerciseName: String,
        prescribedReps: String,
        prescribedLoad: String,
        weightValue: String,
        weightUnit: String,
        setsDone: Int,
        setsTotal: Int,
        variant: LiveActivityRestContentVariant,
        restStartDate: Date,
        restEndDate: Date,
        target: LiveActivityRestTarget? = nil
    ) {
        self.exerciseName = exerciseName
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.weightValue = weightValue
        self.weightUnit = weightUnit
        self.setsDone = setsDone
        self.setsTotal = setsTotal
        self.variant = variant
        self.restStartDate = restStartDate
        self.restEndDate = restEndDate
        self.target = target
    }

    var setsLeft: Int {
        max(setsTotal - setsDone, 0)
    }

    var setsLeftText: String {
        setsLeft == 1 ? "1 set left" : "\(setsLeft) sets left"
    }
}

enum LiveActivityInvalidationPolicy {
    static let postRestReadyDuration: TimeInterval = 30 * 60

    static func isReady(_ content: LiveActivityRestContent, at date: Date) -> Bool {
        date >= content.restEndDate
    }

    static func postRestCapEndDate(for content: LiveActivityRestContent) -> Date {
        content.restEndDate.addingTimeInterval(postRestReadyDuration)
    }

    static func shouldEndReadyReminder(for content: LiveActivityRestContent, at date: Date) -> Bool {
        date >= postRestCapEndDate(for: content)
    }

    static func shouldEnd(for event: LiveActivityInvalidationEvent) -> Bool {
        switch event {
        case .moveOn, .sheetSwitch, .signOut:
            true
        case .restExpired, .appBackgrounded, .syncStateChanged, .settingsOpened, .developerToolsOpened:
            false
        }
    }

    @MainActor
    static func shouldEnd(
        _ content: LiveActivityRestContent,
        displayedSession: Session?,
        currentSession: Session?
    ) -> Bool {
        guard let displayedSession, let currentSession else { return true }
        guard displayedSession === currentSession else { return true }
        guard let target = content.target else { return true }
        guard
            let targetSession = SessionProgressTracker().sessionsInCurrentWeek(for: currentSession).first(where: {
                sessionIdentity(for: $0) == target.session
            })
        else {
            return true
        }

        let set = targetSession.exercises
            .first { $0.order == target.setID.exerciseOrder }?
            .sets
            .first { $0.index == target.setID.setIndex }
        return set?.isPending != true
    }

    @MainActor
    private static func sessionIdentity(for session: Session) -> LiveActivitySessionIdentity {
        LiveActivitySessionIdentity(
            blockTab: session.week?.block?.tabName,
            weekNumber: session.week?.number,
            dayNumber: session.dayNumber
        )
    }
}

@MainActor
enum LiveActivityRestContentBuilder {
    private struct RestTargetSet {
        let session: Session
        let exercise: Exercise
        let set: ExerciseSet
    }

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

        let pendingCount = target.exercise.pendingSetCount
        let totalCount = target.exercise.sets.count
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
            restEndDate: restEndDate,
            target: LiveActivityRestTarget(
                session: sessionIdentity(for: target.session),
                setID: ActiveSetID(exerciseOrder: target.exercise.order, setIndex: target.set.index)
            )
        )
    }

    private static func targetSet(
        afterLogging loggedSet: ExerciseSet,
        in session: Session,
        supersetState: SupersetState?
    ) -> RestTargetSet? {
        if let supersetSetID = supersetState?.nextSetID(after: loggedSet, in: session) {
            if let target = set(for: supersetSetID, in: session) {
                return RestTargetSet(session: session, exercise: target.exercise, set: target.set)
            }
        }

        if let sessionTarget = nextPendingSet(after: loggedSet, in: session) {
            return RestTargetSet(session: session, exercise: sessionTarget.exercise, set: sessionTarget.set)
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
            .first { $0.set.isPending }
            ?? orderedSets.first { $0.set.isPending }
    }

    private static func openExerciseFallback(for session: Session) -> RestTargetSet? {
        SessionProgressTracker().sessionsInCurrentWeek(for: session)
            .filter { $0.dayNumber < session.dayNumber }
            .sorted { $0.dayNumber < $1.dayNumber }
            .lazy
            .compactMap { openSession in
                firstPendingSet(in: openSession).map {
                    RestTargetSet(session: openSession, exercise: $0.exercise, set: $0.set)
                }
            }
            .first
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
        orderedSets(in: session).first { $0.set.isPending }
    }

    private static func sessionIdentity(for session: Session) -> LiveActivitySessionIdentity {
        LiveActivitySessionIdentity(
            blockTab: session.week?.block?.tabName,
            weekNumber: session.week?.number,
            dayNumber: session.dayNumber
        )
    }
}
