import Foundation
import Observation

@MainActor
protocol SessionLoggingAdapter {
    func log(_ set: ExerciseSet, as log: SetLog) throws
    func skip(_ set: ExerciseSet) throws
    func deleteLog(for set: ExerciseSet) throws
}

@MainActor
protocol SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error)
    func requestPendingWriteFlush()
}

@MainActor
protocol SessionLiveActivityAdapter {
    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String)
    func end()
    func endIfInvalidated(at liveEdge: LiveEdge)
}

/// Whether Move On and the Open Exercises are offered, and where they take the athlete.
@MainActor
protocol SessionNavigationAdapter {
    var canMoveOn: Bool { get }
    var openExercises: [Exercise] { get }
    func requestMoveOnCelebration()
    func show(_ address: SessionAddress)
}

@MainActor
protocol SessionTransitionClock {
    func sleep(for duration: Duration) async
}

enum SessionCoordinatorError: Error {
    case missingSession
    case missingLoggingAdapter
}

enum PairingMode: Equatable, Sendable {
    case inactive
    case selecting(sourceOrder: Int)
    case confirming(sourceOrder: Int, targetOrder: Int)
}

enum PairingTapResult: Equatable, Sendable {
    case ignored
    case cancelled
    case unavailable
    case confirming
}

extension WorkoutStore: SessionLoggingAdapter {}

extension WorkoutStore: SessionNavigationAdapter {}

struct SessionPendingWriteSyncAdapter: SessionSyncAdapter {
    let sync: SyncCoordinator
    let settings: SettingsStore

    func reportLocalWriteFailure(_ error: any Error) {
        sync.reportLocalWriteFailure(error)
    }

    func requestPendingWriteFlush() {
        guard let id = settings.spreadsheetId else { return }
        // Awaiting it would keep flushes apart, which changes when Set Logs are flushed (#702).
        // swiftlint:disable:next unstructured_task_is_held
        Task { await sync.flushPending(spreadsheetId: id) }
    }
}

private struct MissingSessionLoggingAdapter: SessionLoggingAdapter {
    func log(_ set: ExerciseSet, as log: SetLog) throws {
        throw SessionCoordinatorError.missingLoggingAdapter
    }

    func skip(_ set: ExerciseSet) throws {
        throw SessionCoordinatorError.missingLoggingAdapter
    }

    func deleteLog(for set: ExerciseSet) throws {
        throw SessionCoordinatorError.missingLoggingAdapter
    }
}

private struct NoopSessionSyncAdapter: SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error) {}
    func requestPendingWriteFlush() {}
}

private struct NoopSessionLiveActivityAdapter: SessionLiveActivityAdapter {
    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {}
    func end() {}
    func endIfInvalidated(at liveEdge: LiveEdge) {}
}

private struct NoopSessionNavigationAdapter: SessionNavigationAdapter {
    var canMoveOn: Bool { false }
    var openExercises: [Exercise] { [] }
    func requestMoveOnCelebration() {}
    func show(_ address: SessionAddress) {}
}

private struct TaskSessionTransitionClock: SessionTransitionClock {
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

enum ExercisePairingAvailability: Equatable, Sendable {
    case inactive
    case available
    case unavailable
}

struct SessionExerciseRenderConfig {
    let exercise: Exercise
    let activeSetID: ActiveSetID?
    let expandedLoggedSetID: ActiveSetID?
    let savedLoggedSetID: ActiveSetID?
    let pairingAvailability: ExercisePairingAvailability
    let lastPerformedPresentation: LastPerformedCardPresentation?
}

struct SessionSupersetRenderConfig {
    let presentation: ActiveSupersetPresentation
    let exercises: [Exercise]
    let lastPerformedPresentation: LastPerformedCardPresentation?
}

struct SessionHiddenPairedExerciseRenderConfig {
    let exercise: Exercise
    let containerExerciseOrder: Int
}

private struct SessionRenderContext {
    let supersetByContainerOrder: [Int: SupersetSectionState]
    let containerOrderByPairedExerciseOrder: [Int: Int]
    let pairingSourceOrder: Int?
    let lastPerformedLookup: LastPerformedLookupSnapshot?
}

enum SessionRenderItem {
    case exercise(SessionExerciseRenderConfig)
    case superset(SessionSupersetRenderConfig)
    case hiddenPairedExercise(SessionHiddenPairedExerciseRenderConfig)

    var id: String {
        switch self {
        case .exercise(let config):
            "exercise-\(config.exercise.order)"
        case .superset(let config):
            "superset-\(config.presentation.containerExerciseOrder ?? Int.min)"
        case .hiddenPairedExercise(let config):
            "hidden-paired-exercise-\(config.exercise.order)"
        }
    }

    var exerciseConfig: SessionExerciseRenderConfig? {
        guard case .exercise(let config) = self else { return nil }
        return config
    }
}

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var session: Session?
    private(set) var savedLoggedSetID: ActiveSetID?
    private(set) var pairingMode: PairingMode = .inactive

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    @ObservationIgnored private var loggingAdapter: any SessionLoggingAdapter
    @ObservationIgnored private var syncAdapter: any SessionSyncAdapter
    @ObservationIgnored private var liveActivityAdapter: any SessionLiveActivityAdapter
    @ObservationIgnored private var navigationAdapter: any SessionNavigationAdapter
    @ObservationIgnored private var motion: any SessionMotionPerforming
    @ObservationIgnored private var liveEdge: (Session) -> LiveEdge = { _ in .browsedAway }
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    @ObservationIgnored private var restTimer: RestTimer?
    @ObservationIgnored private var standardRestDuration: () -> TimeInterval
    @ObservationIgnored private var supersetRestDuration: () -> TimeInterval
    @ObservationIgnored private var pairingConfirmationTask: Task<Void, Never>?

    init(
        session: Session? = nil,
        logging: any SessionLoggingAdapter = MissingSessionLoggingAdapter(),
        sync: any SessionSyncAdapter = NoopSessionSyncAdapter(),
        transitionClock: any SessionTransitionClock = TaskSessionTransitionClock(),
        restTimer: RestTimer? = nil,
        standardRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.standard.timeInterval },
        supersetRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.superset.timeInterval },
        liveActivity: any SessionLiveActivityAdapter = NoopSessionLiveActivityAdapter(),
        navigation: any SessionNavigationAdapter = NoopSessionNavigationAdapter(),
        motion: any SessionMotionPerforming = ImmediateSessionMotion()
    ) {
        self.session = session
        self.navigationAdapter = navigation
        self.motion = motion
        self.focusManager = ActiveSetFocusManager(session: session)
        self.loggingAdapter = logging
        self.syncAdapter = sync
        self.liveActivityAdapter = liveActivity
        self.transitionClock = transitionClock
        self.restTimer = restTimer
        self.standardRestDuration = standardRestDuration
        self.supersetRestDuration = supersetRestDuration
    }

    var activeSetID: ActiveSetID? { focusManager.activeSetID }
    var expandedLoggedSetID: ActiveSetID? { focusManager.expandedLoggedSetID }
    var visualFocusOwner: ActiveSetVisualFocusOwner? { focusManager.visualFocusOwner }

    deinit {
        pairingConfirmationTask?.cancel()
    }

    func bind(to session: Session?) {
        self.session = session
        savedLoggedSetID = nil
        cancelPairing()
        focusManager.reset(to: session)
    }

    // swiftlint:disable:next function_parameter_count
    func bind(
        to session: Session?,
        logging: any SessionLoggingAdapter,
        sync: any SessionSyncAdapter,
        restTimer: RestTimer? = nil,
        standardRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.standard.timeInterval },
        supersetRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.superset.timeInterval },
        liveActivity: (any SessionLiveActivityAdapter)? = nil,
        navigation: any SessionNavigationAdapter,
        motion: any SessionMotionPerforming,
        liveEdge: @escaping (Session) -> LiveEdge
    ) {
        navigationAdapter = navigation
        self.motion = motion
        self.restTimer = restTimer
        self.standardRestDuration = standardRestDuration
        self.supersetRestDuration = supersetRestDuration
        if let liveActivity {
            liveActivityAdapter = liveActivity
        }
        self.liveEdge = liveEdge
        loggingAdapter = logging
        syncAdapter = sync
        bind(to: session)
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterLog(set, in: session)
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterSkip(set, in: session)
    }

    func focus(on set: ExerciseSet) {
        perform(focusManager.motion(forFocusing: set)) {
            focusManager.focus(on: set)
        }
    }

    func log(_ set: ExerciseSet, as log: SetLog) {
        do {
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set)
            try perform(.momentumFlow) {
                try loggingAdapter.log(set, as: log)
                startRest(afterLogging: set, in: session, wasSupersetMember: wasSupersetMember)
                reconcileLiveActivity(for: session)
                advanceAfterLog(set, in: session)
            }
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func skip(_ set: ExerciseSet) {
        do {
            let session = try actionSession(for: set)
            try perform(.skipFadeUp) {
                try loggingAdapter.skip(set)
                reconcileLiveActivity(for: session)
                advanceAfterSkip(set, in: session)
            }
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func deleteLog(for set: ExerciseSet) {
        do {
            let session = try actionSession(for: set)
            try loggingAdapter.deleteLog(for: set)
            restTimer?.cancel(
                ifOriginMatches: Self.activeSetID(for: set),
                originSetObjectID: ObjectIdentifier(set)
            )
            reconcileLiveActivity(for: session)
            focusManager.focus(on: set)
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func updateLoggedSet(_ set: ExerciseSet, as log: SetLog) {
        do {
            let session = try actionSession(for: set)
            let updatedSetID = Self.activeSetID(for: set)
            try loggingAdapter.log(set, as: log)
            savedLoggedSetID = updatedSetID
            reconcileLiveActivity(for: session)
            if focusManager.expandedLoggedSetID == updatedSetID {
                focusManager.collapseLoggedSetReview()
            }
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func canPair(_ exercise: Exercise, in session: Session) -> Bool {
        focusManager.canPair(exercise, in: session)
    }

    @discardableResult
    func createSuperset(from source: Exercise, to target: Exercise, in session: Session) -> Bool {
        focusManager.createSuperset(from: source, to: target, in: session)
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        cancelPairing()
        focusManager.dismissSuperset(containing: exercise, in: session)
    }

    func supersetSections(in session: Session) -> [SupersetSectionState] {
        focusManager.supersetSections(in: session)
    }

    @discardableResult
    func focusNextSupersetSet(for exercise: Exercise, in session: Session) -> Bool {
        guard focusManager.canFocusNextSupersetSet(for: exercise, in: session) else {
            return false
        }

        perform(.focusMorph) {
            focusManager.focusNextSupersetSet(for: exercise, in: session)
        }
        return true
    }

    static func activeSetID(for set: ExerciseSet) -> ActiveSetID? {
        ActiveSetFocusManager.id(for: set)
    }

    private func perform(_ requested: SessionMotion?, _ change: () throws -> Void) rethrows {
        guard let requested, requested.runs(reducingMotion: motion.reducesMotion) else {
            try change()
            return
        }
        try motion.animate(requested, change)
    }

    private func actionSession(for set: ExerciseSet) throws -> Session {
        guard let session = set.exercise?.session else {
            throw SessionCoordinatorError.missingSession
        }

        if self.session !== session {
            bind(to: session)
        }

        return session
    }
}

extension SessionCoordinator {
    func cancelRestForSessionExit() {
        restTimer?.dismiss()
        liveActivityAdapter.end()
    }

    func moveOn() {
        cancelRestForSessionExit()
        navigationAdapter.requestMoveOnCelebration()
    }

    func showSourceSession(of exercise: Exercise) {
        cancelPairing()
        guard let address = exercise.session?.address else { return }
        navigationAdapter.show(address)
    }

    /// What the stage shows for `session` now: the App's one read of focus, pairing, and the live
    /// edge. It reads observed state and never writes it.
    func stage(in session: Session, lookup: LastPerformedLookupSnapshot) -> SessionStage {
        SessionStage(
            session: session,
            focus: focusManager.snapshot(in: session),
            savedLoggedSetID: savedLoggedSetID,
            pairingMode: pairingMode,
            liveEdge: liveEdgeContext(for: session),
            lookup: lookup
        )
    }

    private func liveEdgeContext(for session: Session) -> LiveEdgeContext {
        guard liveEdge(session).isAtLiveEdge else { return .browsedAway }
        return .atLiveEdge(canMoveOn: navigationAdapter.canMoveOn, openExercises: navigationAdapter.openExercises)
    }
}

extension SessionCoordinator {
    fileprivate func isSupersetMember(_ set: ExerciseSet) -> Bool {
        guard let exercise = set.exercise else { return false }
        return focusManager.isPaired(exercise)
    }

    fileprivate func restDuration(for kind: RestKind) -> TimeInterval {
        switch kind {
        case .standard:
            standardRestDuration()
        case .superset:
            supersetRestDuration()
        }
    }

    fileprivate func startRest(afterLogging set: ExerciseSet, in session: Session, wasSupersetMember: Bool) {
        guard
            let restKind = RestTriggerPolicy.restKind(
                afterLogging: set,
                in: session,
                isSupersetMember: wasSupersetMember,
                isRestRunning: restTimer?.isRunning ?? false
            )
        else { return }
        restTimer?.start(
            duration: restDuration(for: restKind),
            origin: Self.activeSetID(for: set),
            originSetObjectID: ObjectIdentifier(set),
            kind: restKind
        )
        startOrUpdateLiveActivity(afterLogging: set, in: session)
    }

    fileprivate func startOrUpdateLiveActivity(afterLogging set: ExerciseSet, in session: Session) {
        let event = LiveActivityProductionEvent(
            source: .userSetLog,
            outcome: .success,
            sessionScope: liveEdge(session).isAtLiveEdge ? .currentSession : .nonCurrentSession
        )
        guard
            LiveActivityCreationPolicy.shouldCreateOrUpdate(for: event),
            let restInterval = restTimer?.interval
        else { return }

        guard
            let content = focusManager.liveActivityRestContent(
                afterLogging: set,
                in: session,
                restStartDate: restInterval.start,
                restEndDate: restInterval.end
            )
        else { return }

        liveActivityAdapter.startOrUpdate(
            restContent: content,
            sessionLabel: liveActivitySessionLabel(for: session)
        )
    }

    fileprivate func reconcileLiveActivity(for session: Session) {
        liveActivityAdapter.endIfInvalidated(at: liveEdge(session))
    }

    fileprivate func liveActivitySessionLabel(for session: Session) -> String {
        if let address = session.address {
            return "Week \(address.week) - Day \(address.day)"
        }
        return "Day \(session.dayNumber)"
    }
}

extension SessionCoordinator {
    func renderItems(
        in session: Session,
        lastPerformedLookup: LastPerformedLookupSnapshot? = nil
    ) -> [SessionRenderItem] {
        let supersetSections = self.supersetSections(in: session)
        let context = SessionRenderContext(
            supersetByContainerOrder: Dictionary(
                uniqueKeysWithValues: supersetSections.compactMap { section in
                    section.presentation.containerExerciseOrder.map { ($0, section) }
                }
            ),
            containerOrderByPairedExerciseOrder: Dictionary(
                uniqueKeysWithValues: supersetSections.flatMap { section in
                    let containerOrder = section.presentation.containerExerciseOrder ?? Int.min
                    return section.exercises
                        .map(\.order)
                        .filter { $0 != containerOrder }
                        .map { ($0, containerOrder) }
                }
            ),
            pairingSourceOrder: pairingSourceOrder,
            lastPerformedLookup: lastPerformedLookup
        )

        return session.exercises
            .sorted { $0.order < $1.order }
            .map { exercise in
                renderItem(for: exercise, in: session, context: context)
            }
    }

    private func renderItem(
        for exercise: Exercise,
        in session: Session,
        context: SessionRenderContext
    ) -> SessionRenderItem {
        if let supersetSection = context.supersetByContainerOrder[exercise.order] {
            return .superset(
                supersetRenderConfig(
                    for: supersetSection,
                    lastPerformedLookup: context.lastPerformedLookup
                )
            )
        }

        if let containerExerciseOrder = context.containerOrderByPairedExerciseOrder[exercise.order] {
            return .hiddenPairedExercise(
                SessionHiddenPairedExerciseRenderConfig(
                    exercise: exercise,
                    containerExerciseOrder: containerExerciseOrder
                )
            )
        }

        return .exercise(exerciseRenderConfig(for: exercise, in: session, context: context))
    }

    private func supersetRenderConfig(
        for section: SupersetSectionState,
        lastPerformedLookup: LastPerformedLookupSnapshot?
    ) -> SessionSupersetRenderConfig {
        let activeExercise = section.exercises.first {
            $0.order == section.presentation.activeExerciseOrder
        }

        return SessionSupersetRenderConfig(
            presentation: section.presentation,
            exercises: section.exercises,
            lastPerformedPresentation: lastPerformedPresentation(
                for: activeExercise,
                lookup: lastPerformedLookup
            )
        )
    }

    private func exerciseRenderConfig(
        for exercise: Exercise,
        in session: Session,
        context: SessionRenderContext
    ) -> SessionExerciseRenderConfig {
        SessionExerciseRenderConfig(
            exercise: exercise,
            activeSetID: activeSetID(scopedTo: exercise),
            expandedLoggedSetID: expandedLoggedSetID(scopedTo: exercise),
            savedLoggedSetID: savedLoggedSetID(scopedTo: exercise),
            pairingAvailability: pairingAvailability(
                for: exercise,
                in: session,
                pairingSourceOrder: context.pairingSourceOrder
            ),
            lastPerformedPresentation: lastPerformedPresentation(
                for: exercise,
                lookup: context.lastPerformedLookup
            )
        )
    }

    private func pairingAvailability(
        for exercise: Exercise,
        in session: Session,
        pairingSourceOrder: Int?
    ) -> ExercisePairingAvailability {
        guard let pairingSourceOrder else { return .inactive }
        if exercise.order == pairingSourceOrder || canPair(exercise, in: session) {
            return .available
        }
        return .unavailable
    }

    private func activeSetID(scopedTo exercise: Exercise) -> ActiveSetID? {
        guard case .activeSet(let activeSetID) = visualFocusOwner(scopedTo: exercise) else { return nil }
        return activeSetID
    }

    private func expandedLoggedSetID(scopedTo exercise: Exercise) -> ActiveSetID? {
        guard case .loggedSetReview(let expandedLoggedSetID) = visualFocusOwner(scopedTo: exercise) else { return nil }
        return expandedLoggedSetID
    }

    private func savedLoggedSetID(scopedTo exercise: Exercise) -> ActiveSetID? {
        guard savedLoggedSetID?.exerciseOrder == exercise.order else { return nil }
        return savedLoggedSetID
    }

    private func visualFocusOwner(scopedTo exercise: Exercise) -> ActiveSetVisualFocusOwner? {
        guard visualFocusOwner?.setID.exerciseOrder == exercise.order else { return nil }
        return visualFocusOwner
    }

    private func lastPerformedPresentation(
        for exercise: Exercise?,
        lookup: LastPerformedLookupSnapshot?
    ) -> LastPerformedCardPresentation? {
        guard let exercise, let lookup else { return nil }
        return LastPerformedCardPresentation(exercise: exercise, lookup: lookup)
    }
}

extension SessionCoordinator {
    @discardableResult
    func beginPairing(from exercise: Exercise, in session: Session) -> Bool {
        guard canPair(exercise, in: session) else { return false }
        pairingConfirmationTask?.cancel()
        pairingConfirmationTask = nil
        pairingMode = .selecting(sourceOrder: exercise.order)
        return true
    }

    func cancelPairing() {
        pairingConfirmationTask?.cancel()
        pairingConfirmationTask = nil
        guard pairingMode != .inactive else { return }
        pairingMode = .inactive
    }

    @discardableResult
    func handlePairingTap(on exercise: Exercise, in session: Session) -> PairingTapResult {
        guard let sourceOrder = pairingSourceOrder else {
            return .ignored
        }
        guard exercise.order != sourceOrder else {
            cancelPairing()
            return .cancelled
        }
        guard canPair(exercise, in: session) else {
            return .unavailable
        }
        guard case .selecting = pairingMode else {
            return .ignored
        }
        pairingMode = .confirming(sourceOrder: sourceOrder, targetOrder: exercise.order)
        confirmPairing(sourceOrder: sourceOrder, targetOrder: exercise.order, in: session)
        return .confirming
    }

    private var pairingSourceOrder: Int? {
        switch pairingMode {
        case .inactive:
            nil
        case .selecting(let sourceOrder), .confirming(let sourceOrder, _):
            sourceOrder
        }
    }

    private func confirmPairing(sourceOrder: Int, targetOrder: Int, in session: Session) {
        pairingConfirmationTask?.cancel()
        let expectedMode = PairingMode.confirming(sourceOrder: sourceOrder, targetOrder: targetOrder)
        let clock = transitionClock
        let duration = pairingConfirmationDuration()

        pairingConfirmationTask = Task { @MainActor [weak self] in
            await clock.sleep(for: duration)
            guard
                !Task.isCancelled,
                let self,
                self.pairingMode == expectedMode
            else { return }

            guard
                let source = session.exercises.first(where: { $0.order == sourceOrder }),
                let target = session.exercises.first(where: { $0.order == targetOrder })
            else {
                self.cancelPairing()
                return
            }

            _ = self.createSuperset(from: source, to: target, in: session)
            self.pairingMode = .inactive
            self.pairingConfirmationTask = nil
        }
    }

    private func pairingConfirmationDuration() -> Duration {
        .nanoseconds(Int64((Theme.pairingConfirmationDuration * 1_000_000_000).rounded()))
    }
}
