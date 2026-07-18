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

        if let sessionTarget = SessionSetOrder.nextPendingSet(after: loggedSet, in: session) {
            return RestTargetSet(session: session, exercise: sessionTarget.exercise, set: sessionTarget.set)
        }

        return openExerciseFallback(for: session)
    }

    /// The widget-only makeup fallback: when the Current Session has no Pending
    /// Set left, point the rest widget at the earliest earlier Current-Week day
    /// that still owes work. The earlier-day selection is the Open Exercise
    /// owner's rule (`SessionProgressTracker.openExercises`); this builder only
    /// projects its first Open Exercise's first Pending Set into a target. The
    /// focus engine deliberately has no counterpart to this fallback.
    private static func openExerciseFallback(for session: Session) -> RestTargetSet? {
        // The rest fallback selects the first Pending Set of the first Open
        // Exercise, walking the same earlier-Day / Pending-Set order the makeup
        // queue uses. Every Open Exercise has a Pending Set by construction, so
        // the first one always yields a target. The Pending-Set walk is owned by
        // `SessionSetOrder`; this builder only projects its first hit.
        guard
            let open = SessionProgressTracker().openExercises(for: session).first,
            let position = SessionSetOrder.firstPendingSet(in: [open.exercise])
        else {
            return nil
        }
        return RestTargetSet(session: open.session, exercise: position.exercise, set: position.set)
    }

    private static func set(
        for setID: ActiveSetID,
        in session: Session
    ) -> SessionSetPosition? {
        SessionSetOrder.orderedSets(in: session).first { $0.setID == setID }
    }

    private static func sessionIdentity(for session: Session) -> LiveActivitySessionIdentity {
        LiveActivitySessionIdentity(
            blockTab: session.week?.block?.tabName,
            weekNumber: session.week?.number,
            dayNumber: session.dayNumber
        )
    }
}
