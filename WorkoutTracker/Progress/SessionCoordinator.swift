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

struct SessionPendingWriteSyncAdapter: SessionSyncAdapter {
    let sync: SyncCoordinator
    let settings: SettingsStore

    func reportLocalWriteFailure(_ error: any Error) {
        sync.reportLocalWriteFailure(error)
    }

    func requestPendingWriteFlush() {
        guard let id = settings.spreadsheetId else { return }
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
    let visualFocusOwner: ActiveSetVisualFocusOwner?
    let activeSetID: ActiveSetID?
    let expandedLoggedSetID: ActiveSetID?
    let savedLoggedSetID: ActiveSetID?
    let activeSetTransition: ActiveSetTransition?
    let retiringTransition: ActiveSetTransition?
    let isCollapsed: Bool
    let showsPairingGrip: Bool
    let pairingAvailability: ExercisePairingAvailability
    let isPairingConfirmation: Bool
    let lastPerformedPresentation: LastPerformedCardPresentation?
}

typealias SessionExerciseRenderItem = SessionExerciseRenderConfig

struct SessionSupersetRenderConfig {
    let presentation: ActiveSupersetPresentation
    let exercises: [Exercise]
    let visualFocusOwner: ActiveSetVisualFocusOwner?
    let activeSetTransition: ActiveSetTransition?
    let retiringTransition: ActiveSetTransition?
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
    let pairingConfirmationOrder: Int?
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

typealias SessionFocusAnimation = (() -> Void) -> Void

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var session: Session?
    private(set) var activeSetID: ActiveSetID?
    private(set) var expandedLoggedSetID: ActiveSetID?
    private(set) var visualFocusOwner: ActiveSetVisualFocusOwner?
    private(set) var savedLoggedSetID: ActiveSetID?
    private(set) var activeSetTransition: ActiveSetTransition?
    private(set) var retiringTransition: ActiveSetTransition?
    private(set) var scrollTargetID: ActiveSetID?
    private(set) var supersetScrollTargetOrder: Int?
    private(set) var pairingMode: PairingMode = .inactive

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    @ObservationIgnored private var loggingAdapter: any SessionLoggingAdapter
    @ObservationIgnored private var syncAdapter: any SessionSyncAdapter
    @ObservationIgnored private var liveActivityAdapter: any SessionLiveActivityAdapter
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    @ObservationIgnored private var restTimer: RestTimer?
    @ObservationIgnored private var standardRestDuration: () -> TimeInterval
    @ObservationIgnored private var supersetRestDuration: () -> TimeInterval
    @ObservationIgnored private var retirementTask: Task<Void, Never>?
    @ObservationIgnored private var pairingConfirmationTask: Task<Void, Never>?
    private var renderRevision = 0

    init(
        session: Session? = nil,
        logging: any SessionLoggingAdapter = MissingSessionLoggingAdapter(),
        sync: any SessionSyncAdapter = NoopSessionSyncAdapter(),
        transitionClock: any SessionTransitionClock = TaskSessionTransitionClock(),
        restTimer: RestTimer? = nil,
        standardRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.standard.timeInterval },
        supersetRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.superset.timeInterval },
        liveActivity: any SessionLiveActivityAdapter = NoopSessionLiveActivityAdapter()
    ) {
        self.session = session
        self.focusManager = ActiveSetFocusManager(session: session)
        self.loggingAdapter = logging
        self.syncAdapter = sync
        self.liveActivityAdapter = liveActivity
        self.transitionClock = transitionClock
        self.restTimer = restTimer
        self.standardRestDuration = standardRestDuration
        self.supersetRestDuration = supersetRestDuration
        syncFocusState()
    }

    deinit {
        retirementTask?.cancel()
        pairingConfirmationTask?.cancel()
    }

    func configure(
        logging: any SessionLoggingAdapter,
        sync: any SessionSyncAdapter
    ) {
        loggingAdapter = logging
        syncAdapter = sync
    }

    func bind(to session: Session?) {
        self.session = session
        savedLoggedSetID = nil
        cancelPairing()
        clearRetiringTransition()
        focusManager.reset(to: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func bind(
        to session: Session?,
        logging: any SessionLoggingAdapter,
        sync: any SessionSyncAdapter,
        restTimer: RestTimer? = nil,
        standardRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.standard.timeInterval },
        supersetRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.superset.timeInterval },
        liveActivity: (any SessionLiveActivityAdapter)? = nil
    ) {
        self.restTimer = restTimer
        self.standardRestDuration = standardRestDuration
        self.supersetRestDuration = supersetRestDuration
        if let liveActivity {
            liveActivityAdapter = liveActivity
        }
        configure(logging: logging, sync: sync)
        bind(to: session)
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterLog(set, in: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterSkip(set, in: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func focus(on set: ExerciseSet, animateFocus: SessionFocusAnimation? = nil) {
        performFocusUpdate(animateFocus) {
            focusManager.focus(on: set)
            if case .loggedSetReview = focusManager.visualFocusOwner {
                clearRetiringTransition()
            }
            syncFocusState()
            invalidateRenderItems()
        }
    }

    func collapseLoggedSetReview() {
        focusManager.collapseLoggedSetReview()
        syncFocusState()
        invalidateRenderItems()
    }

    func log(_ set: ExerciseSet, as log: SetLog, animateFocus: SessionFocusAnimation? = nil) {
        do {
            let wasCurrentSession = set.exercise?.session === self.session
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set, in: session)
            try loggingAdapter.log(set, as: log)
            let decision = RestTriggerPolicy.decision(
                afterLogging: set,
                in: session,
                isSupersetMember: wasSupersetMember
            )
            let restKind = restKind(for: decision, wasSupersetMember: wasSupersetMember)
            if let restKind {
                restTimer?.start(
                    duration: restDuration(for: restKind),
                    origin: Self.activeSetID(for: set),
                    originSetObjectID: ObjectIdentifier(set),
                    kind: restKind
                )
                startOrUpdateLiveActivity(afterLogging: set, in: session, wasCurrentSession: wasCurrentSession)
            }
            performFocusUpdate(animateFocus) {
                advanceAfterLog(set, in: session)
            }
            retireActiveSetTransition()
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func skip(_ set: ExerciseSet, animateFocus: SessionFocusAnimation? = nil) {
        do {
            let session = try actionSession(for: set)
            try loggingAdapter.skip(set)
            performFocusUpdate(animateFocus) {
                advanceAfterSkip(set, in: session)
            }
            retireActiveSetTransition()
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func deleteLog(for set: ExerciseSet) {
        do {
            _ = try actionSession(for: set)
            try loggingAdapter.deleteLog(for: set)
            restTimer?.cancel(
                ifOriginMatches: Self.activeSetID(for: set),
                originSetObjectID: ObjectIdentifier(set)
            )
            focus(on: set)
            clearRetiringTransition()
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func cancelRestForSessionExit() {
        restTimer?.dismiss()
    }

    func updateLoggedSet(_ set: ExerciseSet, as log: SetLog) {
        do {
            _ = try actionSession(for: set)
            let updatedSetID = Self.activeSetID(for: set)
            try loggingAdapter.log(set, as: log)
            savedLoggedSetID = updatedSetID
            if focusManager.expandedLoggedSetID == updatedSetID {
                focusManager.collapseLoggedSetReview()
            }
            syncFocusState()
            clearRetiringTransition()
            invalidateRenderItems()
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
        let created = focusManager.createSuperset(from: source, to: target, in: session)
        syncFocusState()
        invalidateRenderItems()
        return created
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        cancelPairing()
        focusManager.dismissSuperset(containing: exercise, in: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func supersetSections(in session: Session) -> [SupersetSectionState] {
        _ = renderRevision
        return focusManager.supersetSections(in: session)
    }

    @discardableResult
    func focusNextSupersetSet(
        for exercise: Exercise,
        in session: Session,
        animateFocus: SessionFocusAnimation? = nil
    ) -> Bool {
        guard supersetFocusTargetID(for: exercise, in: session) != nil else {
            return false
        }

        var focused = false
        performFocusUpdate(animateFocus) {
            focused = focusManager.focusNextSupersetSet(for: exercise, in: session)
            syncFocusState()
            invalidateRenderItems()
        }
        return focused
    }

    func clearTransition(_ transition: ActiveSetTransition) {
        focusManager.clearTransition(transition)
        syncFocusState()
        invalidateRenderItems()
    }

    func reexpand(_ exercise: Exercise) {
        focusManager.reexpand(exercise)
        invalidateRenderItems()
    }

    static func activeSetID(for set: ExerciseSet) -> ActiveSetID? {
        ActiveSetFocusManager.id(for: set)
    }

    private func syncFocusState() {
        activeSetID = focusManager.activeSetID
        expandedLoggedSetID = focusManager.expandedLoggedSetID
        visualFocusOwner = focusManager.visualFocusOwner
        activeSetTransition = focusManager.activeSetTransition
        scrollTargetID = focusManager.scrollTargetID
        supersetScrollTargetOrder = focusManager.supersetScrollTargetOrder
    }

    private func invalidateRenderItems() {
        renderRevision += 1
    }

    private func performFocusUpdate(
        _ animation: SessionFocusAnimation?,
        update: () -> Void
    ) {
        if let animation {
            animation(update)
        } else {
            update()
        }
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

    private func retireActiveSetTransition() {
        guard let transition = activeSetTransition else { return }

        retirementTask?.cancel()
        retiringTransition = transition
        let duration = transitionClearDuration(for: transition)
        let clock = transitionClock

        retirementTask = Task { @MainActor [weak self] in
            await clock.sleep(for: duration)
            guard
                !Task.isCancelled,
                let self,
                self.retiringTransition == transition
            else { return }

            self.retiringTransition = nil
            self.clearTransition(transition)
            self.retirementTask = nil
        }
    }

    private func clearRetiringTransition() {
        retirementTask?.cancel()
        retirementTask = nil
        retiringTransition = nil
    }

    private func transitionClearDuration(for transition: ActiveSetTransition) -> Duration {
        let seconds =
            switch transition.kind {
            case .momentumFlow:
                Theme.momentumFlowTotalDuration
            case .softFadeUp:
                Theme.skipFadeUpDuration
            case .collapseAndRise:
                Theme.momentumDropDuration
                    + Theme.exerciseCompletionBeatDuration
                    + Theme.momentumRiseDuration
            }
        return .nanoseconds(Int64((seconds * 1_000_000_000).rounded()))
    }
}

extension SessionCoordinator {
    fileprivate func supersetFocusTargetID(for exercise: Exercise, in session: Session) -> ActiveSetID? {
        let isInSuperset = focusManager.supersetSections(in: session).contains { section in
            section.exercises.contains { $0 === exercise }
        }
        guard isInSuperset else { return nil }

        let targetID = exercise.sets
            .filter { $0.state == .pending }
            .sorted { $0.index < $1.index }
            .first
            .flatMap(Self.activeSetID(for:))
        guard targetID != activeSetID else { return nil }
        return targetID
    }

    fileprivate func isSupersetMember(_ set: ExerciseSet, in session: Session) -> Bool {
        guard let exercise = set.exercise else { return false }
        return focusManager.supersetSections(in: session).contains { section in
            section.exercises.contains { $0 === exercise }
        }
    }

    fileprivate func restKind(for decision: RestTriggerDecision, wasSupersetMember: Bool) -> RestKind? {
        if case .start(let superset) = decision {
            return superset ? .superset : .standard
        }
        guard restTimer?.isRunning == true else { return nil }
        return wasSupersetMember ? .superset : .standard
    }

    fileprivate func restDuration(for kind: RestKind) -> TimeInterval {
        switch kind {
        case .standard:
            standardRestDuration()
        case .superset:
            supersetRestDuration()
        }
    }

    fileprivate func startOrUpdateLiveActivity(
        afterLogging set: ExerciseSet,
        in session: Session,
        wasCurrentSession: Bool
    ) {
        let event = LiveActivityProductionEvent(
            source: .userSetLog,
            outcome: .success,
            sessionScope: wasCurrentSession ? .currentSession : .nonCurrentSession
        )
        guard
            LiveActivityCreationPolicy.shouldCreateOrUpdate(for: event),
            let restTimer,
            let restEndDate = restTimer.deadline
        else { return }

        let restStartDate = restEndDate.addingTimeInterval(-restTimer.duration)
        guard
            let content = focusManager.liveActivityRestContent(
                afterLogging: set,
                in: session,
                restStartDate: restStartDate,
                restEndDate: restEndDate
            )
        else { return }

        liveActivityAdapter.startOrUpdate(
            restContent: content,
            sessionLabel: liveActivitySessionLabel(for: session)
        )
    }

    fileprivate func liveActivitySessionLabel(for session: Session) -> String {
        if let week = session.week {
            return "Week \(week.number) - Day \(session.dayNumber)"
        }
        return "Day \(session.dayNumber)"
    }
}

extension SessionCoordinator {
    func exerciseRenderItems() -> [SessionExerciseRenderItem] {
        guard let session else { return [] }
        return exerciseRenderItems(in: session)
    }

    func exerciseRenderItems(in session: Session) -> [SessionExerciseRenderItem] {
        renderItems(in: session).compactMap(\.exerciseConfig)
    }

    func renderItems(
        lastPerformedLookup: LastPerformedLookupSnapshot? = nil
    ) -> [SessionRenderItem] {
        guard let session else { return [] }
        return renderItems(in: session, lastPerformedLookup: lastPerformedLookup)
    }

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
            pairingConfirmationOrder: pairingConfirmationOrder,
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
        let exerciseOrders = Set(section.exercises.map(\.order))
        let activeExercise = section.exercises.first {
            $0.order == section.presentation.activeExerciseOrder
        }

        return SessionSupersetRenderConfig(
            presentation: section.presentation,
            exercises: section.exercises,
            visualFocusOwner: section.presentation.activeSetID.map(ActiveSetVisualFocusOwner.activeSet),
            activeSetTransition: transition(activeSetTransition, scopedTo: exerciseOrders),
            retiringTransition: transition(retiringTransition, scopedTo: exerciseOrders),
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
            visualFocusOwner: visualFocusOwner(scopedTo: exercise),
            activeSetID: activeSetID(scopedTo: exercise),
            expandedLoggedSetID: expandedLoggedSetID(scopedTo: exercise),
            savedLoggedSetID: savedLoggedSetID(scopedTo: exercise),
            activeSetTransition: transition(activeSetTransition, scopedTo: [exercise.order]),
            retiringTransition: transition(retiringTransition, scopedTo: [exercise.order]),
            isCollapsed: focusManager.isCollapsed(exercise),
            showsPairingGrip: context.pairingSourceOrder != nil,
            pairingAvailability: pairingAvailability(
                for: exercise,
                in: session,
                pairingSourceOrder: context.pairingSourceOrder
            ),
            isPairingConfirmation: context.pairingConfirmationOrder == exercise.order,
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

    private func transition(
        _ transition: ActiveSetTransition?,
        scopedTo exerciseOrders: Set<Int>
    ) -> ActiveSetTransition? {
        guard let transition else { return nil }
        if exerciseOrders.contains(transition.outgoingSetID.exerciseOrder) {
            return transition
        }
        if transition.incomingSetID.map({ exerciseOrders.contains($0.exerciseOrder) }) == true {
            return transition
        }
        if transition.completedExerciseOrder.map(exerciseOrders.contains) == true {
            return transition
        }
        return nil
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
        invalidateRenderItems()
        return true
    }

    func cancelPairing() {
        pairingConfirmationTask?.cancel()
        pairingConfirmationTask = nil
        guard pairingMode != .inactive else { return }
        pairingMode = .inactive
        invalidateRenderItems()
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
        invalidateRenderItems()
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

    private var pairingConfirmationOrder: Int? {
        switch pairingMode {
        case .inactive, .selecting:
            nil
        case .confirming(_, let targetOrder):
            targetOrder
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
            self.invalidateRenderItems()
        }
    }

    private func pairingConfirmationDuration() -> Duration {
        .nanoseconds(Int64((Theme.pairingConfirmationDuration * 1_000_000_000).rounded()))
    }
}
