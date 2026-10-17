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

@MainActor
protocol SessionNavigationAdapter: AnyObject {
    var canMoveOn: Bool { get }
    var openExercises: [Exercise] { get }
    var currentSession: Session? { get }
    func liveEdge(for session: Session) -> LiveEdge
    func requestMoveOnCelebration()
    func show(_ address: SessionAddress)
    func showCurrent()
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

    var sourceOrder: Int? {
        switch self {
        case .inactive: nil
        case .selecting(let sourceOrder), .confirming(let sourceOrder, _): sourceOrder
        }
    }
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

private final class NoopSessionNavigationAdapter: SessionNavigationAdapter {
    var canMoveOn: Bool { false }
    var openExercises: [Exercise] { [] }
    var currentSession: Session? { nil }
    func liveEdge(for session: Session) -> LiveEdge { .browsedAway }
    func requestMoveOnCelebration() {}
    func show(_ address: SessionAddress) {}
    func showCurrent() {}
}

private struct TaskSessionTransitionClock: SessionTransitionClock {
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
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
    private var navigationAdapter: any SessionNavigationAdapter
    @ObservationIgnored private var motion: any SessionMotionPerforming
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    @ObservationIgnored private var restTimer: RestTimer?
    @ObservationIgnored private var standardRestDuration: () -> TimeInterval
    @ObservationIgnored private var supersetRestDuration: () -> TimeInterval
    @ObservationIgnored private var pairingConfirmationTask: Task<Void, Never>?
    /// Nil leaves the mic off every card.
    @ObservationIgnored private let dictation: SetDictation?
    @ObservationIgnored private var dictatingSession: Session?
    @ObservationIgnored private var spokenWriteHoldTask: Task<Void, Never>?
    /// Nil until the Session screen binds the stage, which hears no request before then.
    private var entry: AppEntryInbox?

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
        motion: any SessionMotionPerforming = ImmediateSessionMotion(),
        dictation: SetDictation? = nil
    ) {
        self.session = session
        self.dictation = dictation
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

    deinit {
        pairingConfirmationTask?.cancel()
        spokenWriteHoldTask?.cancel()
    }

    func bind(to session: Session?) {
        self.session = session
        savedLoggedSetID = nil
        cancelPairing()
        cancelSpokenWriteHold()
        dictation?.dismiss()
        focusManager.reset(to: session)
        answerEntry()
    }

    /// The Session screen hands over everything without a default here, so it cannot forget one.
    func bind(  // swiftlint:disable:this function_parameter_count
        to session: Session?,
        logging: any SessionLoggingAdapter,
        sync: any SessionSyncAdapter,
        restTimer: RestTimer? = nil,
        standardRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.standard.timeInterval },
        supersetRestDuration: @escaping () -> TimeInterval = { RestDurationSetting.superset.timeInterval },
        liveActivity: (any SessionLiveActivityAdapter)? = nil,
        navigation: any SessionNavigationAdapter,
        motion: any SessionMotionPerforming,
        entry: AppEntryInbox
    ) {
        if navigationAdapter !== navigation {
            navigationAdapter = navigation
        }
        self.motion = motion
        self.restTimer = restTimer
        self.standardRestDuration = standardRestDuration
        self.supersetRestDuration = supersetRestDuration
        if let liveActivity {
            liveActivityAdapter = liveActivity
        }
        loggingAdapter = logging
        syncAdapter = sync
        if self.entry !== entry {
            self.entry = entry
        }
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
        self.log(set, as: log, from: .card)
    }

    /// A held Set takes no write from its card: only its Clear menu changes it.
    func log(_ setLog: SetLog, for slot: SetCardSlot) {
        switch slot.mode.cardMode {
        case .logging:
            log(slot.set, as: setLog)
        case .reviewingLogged:
            updateLoggedSet(slot.set, as: setLog)
        case .held:
            break
        }
    }

    func skip(_ set: ExerciseSet) {
        skip(set, from: .card)
    }

    func skip(for slot: SetCardSlot) {
        switch slot.mode.cardMode {
        case .logging, .reviewingLogged:
            skip(slot.set)
        case .held:
            break
        }
    }

    private func log(_ set: ExerciseSet, as log: SetLog, from source: WriteSource) {
        do {
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set)
            try perform(.momentumFlow) {
                try loggingAdapter.log(set, as: log)
                startRest(afterLogging: set, in: session, wasSupersetMember: wasSupersetMember)
                reconcileLiveActivity(for: session)
                switch source {
                case .card: advanceAfterLog(set, in: session)
                case .speech: advanceAfterSpokenWrite(set, in: session, wasSupersetMember: wasSupersetMember)
                }
            }
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    private func skip(_ set: ExerciseSet, from source: WriteSource) {
        do {
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set)
            try perform(.skipFadeUp) {
                try loggingAdapter.skip(set)
                reconcileLiveActivity(for: session)
                switch source {
                case .card: advanceAfterSkip(set, in: session)
                case .speech: advanceAfterSpokenWrite(set, in: session, wasSupersetMember: wasSupersetMember)
                }
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
            perform(nil) { focusManager.focus(on: set) }
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

    @discardableResult
    func createSuperset(from source: Exercise, to target: Exercise, in session: Session) -> Bool {
        focusManager.createSuperset(from: source, to: target, in: session)
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        cancelPairing()
        focusManager.dismissSuperset(containing: exercise, in: session)
    }

    @discardableResult
    func focusNextSupersetSet(for exercise: Exercise, in session: Session) -> Bool {
        var focused = false
        perform(.cut) {
            focused = focusManager.focusNextSupersetSet(for: exercise, in: session)
        }
        return focused
    }

    static func activeSetID(for set: ExerciseSet) -> ActiveSetID? {
        ActiveSetFocusManager.id(for: set)
    }

    /// Every change to which Set the card shows runs through here, so a press's rejection or fill
    /// never outlives the card it was shown on.
    private func perform(_ requested: SessionMotion?, _ change: () throws -> Void) rethrows {
        dictation?.dismiss()
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
        guard navigationAdapter.liveEdge(for: session).isAtLiveEdge else { return .browsedAway }
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
            sessionScope: navigationAdapter.liveEdge(for: session).isAtLiveEdge ? .currentSession : .nonCurrentSession
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
        liveActivityAdapter.endIfInvalidated(at: navigationAdapter.liveEdge(for: session))
    }

    fileprivate func liveActivitySessionLabel(for session: Session) -> String {
        if let address = session.address {
            return "Week \(address.week) - Day \(address.day)"
        }
        return "Day \(session.dayNumber)"
    }
}

extension SessionCoordinator {
    @discardableResult
    func beginPairing(from exercise: Exercise, in session: Session) -> Bool {
        guard focusManager.canPair(exercise, in: session) else { return false }
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
        guard let sourceOrder = pairingMode.sourceOrder else {
            return .ignored
        }
        guard exercise.order != sourceOrder else {
            cancelPairing()
            return .cancelled
        }
        guard focusManager.canPair(exercise, in: session) else {
            return .unavailable
        }
        guard case .selecting = pairingMode else {
            return .ignored
        }
        pairingMode = .confirming(sourceOrder: sourceOrder, targetOrder: exercise.order)
        confirmPairing(sourceOrder: sourceOrder, targetOrder: exercise.order, in: session)
        return .confirming
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

/// How a write reached the card. A tap moves the card on at once; a spoken write keeps the Set on
/// the card first, so the athlete can glance at what was heard and undo it.
private enum WriteSource {
    case card
    case speech
}

extension SessionCoordinator {
    /// How long the card keeps a Set written by speech before it moves on.
    static let spokenWriteHold: Duration = .seconds(4)

    /// Nil keeps the mic off the card: no transcriber, or a Set that is not Pending and being logged.
    func cardDictation(for slot: SetCardSlot) -> SetCardDictation? {
        guard let dictation, slot.mode == .logging, slot.set.isPending, let setID = Self.activeSetID(for: slot.set) else { return nil }
        return SetCardDictation(dictation.state, for: setID)
    }

    func startDictation(for set: ExerciseSet) {
        guard let dictation, let setID = Self.activeSetID(for: set), let session, set.exercise?.session === session else { return }
        dictatingSession = session
        dictation.start(for: setID)
    }

    /// Writes what the athlete said through the same paths as the card's Log and skip, with what
    /// they left unsaid read from `shown`, the values of `set`'s card. A press begun on another
    /// Session or for another Set, or for a Set no longer Pending once the transcript is in, writes
    /// nothing.
    func finishDictation(of set: ExerciseSet, resolvingAgainst shown: SetLogDraft) async -> SetDictation.Outcome? {
        guard let dictation, let setID = dictation.state.listeningSetID else { return nil }
        guard let session = sessionOfPress(for: setID, releasedOn: set) else {
            await dictation.cancel()
            return nil
        }
        return write(await dictation.finish(for: setID, in: SpokenSetContext(for: set, showing: shown)), heardFor: setID, in: session)
    }

    /// The Session `setID`'s press began in, while it is on stage and `set` is that Set in it.
    private func sessionOfPress(for setID: ActiveSetID, releasedOn set: ExerciseSet) -> Session? {
        guard let session, session === dictatingSession, Self.activeSetID(for: set) == setID, set.exercise?.session === session else {
            return nil
        }
        return session
    }

    private func pendingSet(at setID: ActiveSetID, in session: Session) -> ExerciseSet? {
        guard self.session === session, let set = session.set(at: setID), set.isPending else { return nil }
        return set
    }

    /// A Set no longer Pending once the transcript is in takes nothing, and its outcome goes.
    private func write(_ outcome: SetDictation.Outcome?, heardFor setID: ActiveSetID, in session: Session) -> SetDictation.Outcome? {
        guard let outcome else { return nil }
        guard let set = pendingSet(at: setID, in: session) else {
            dictation?.dismiss()
            return nil
        }
        write(outcome, to: set)
        return outcome
    }

    private func write(_ outcome: SetDictation.Outcome, to set: ExerciseSet) {
        switch outcome {
        case .logged(let setLog, _): log(set, as: setLog, from: .speech)
        case .skipped: skip(set, from: .speech)
        case .filled, .rejected: break
        }
    }

    /// Stops the press for `set` whose control left the screen, writing nothing. A control that
    /// leaves while another card's press runs, as an outgoing card's can after the incoming one
    /// starts listening, stops nothing.
    func cancelDictation(of set: ExerciseSet) async {
        guard let dictation, let setID = dictation.state.listeningSetID, Self.activeSetID(for: set) == setID,
            set.exercise?.session === dictatingSession
        else { return }
        await dictation.cancel()
    }

    func dismissDictation() {
        dictation?.dismiss()
    }

    /// The athlete opened the held Set's Clear menu: its time stops, and the card keeps the Set until
    /// the menu closes or a Clear undoes the write.
    func suspendSpokenWriteHold() {
        guard focusManager.isHoldingSpokenWrite else { return }
        cancelSpokenWriteHold()
    }

    /// The athlete touched the held card or closed its Clear menu without a Clear, or its time ran
    /// out: it moves on now. A hold already ended by a tap or a Clear stays ended.
    func endSpokenWriteHold() {
        guard focusManager.isHoldingSpokenWrite else { return }
        perform(.momentumFlow) { focusManager.endHoldAfterSpokenWrite() }
    }

    /// A Superset's stage shows no held Set, as it shows no review, so a spoken write there moves
    /// on at once.
    fileprivate func advanceAfterSpokenWrite(_ set: ExerciseSet, in session: Session, wasSupersetMember: Bool) {
        guard focusManager.advanceAfterSpokenWrite(set, in: session, holding: !wasSupersetMember) else { return }
        spokenWriteHoldTask?.cancel()
        let clock = transitionClock
        spokenWriteHoldTask = Task { @MainActor [weak self] in
            await clock.sleep(for: Self.spokenWriteHold)
            guard !Task.isCancelled else { return }
            self?.endSpokenWriteHold()
        }
    }

    private func cancelSpokenWriteHold() {
        spokenWriteHoldTask?.cancel()
        spokenWriteHoldTask = nil
    }
}

@MainActor
extension Session {
    fileprivate func set(at setID: ActiveSetID) -> ExerciseSet? {
        exercises.first { $0.order == setID.exerciseOrder }?.sets.first { $0.index == setID.setIndex }
    }
}

/// What a request to say the Current Session's active Set does next.
enum SetDictationEntryRoute: Equatable {
    /// The stage has no Session yet, as on a cold launch.
    case wait
    case showCurrentSession
    /// The card shows a logged Set in place of the active one.
    case uncoverActiveSet
    /// The card for this Set takes the request when it shows.
    case listen(ActiveSetID)
    /// Nothing to listen for, so the request ends with the stage where it is.
    case drop
}

extension SessionCoordinator {
    /// Closes whatever covers the stage and moves it toward the Current Session's active Set for
    /// a waiting request, or ends a request there is nothing to listen for, leaving the stage as
    /// it is. Run when a request arrives and on every bind.
    func answerEntry() {
        guard let entry, let route = entryRoute else { return }
        switch route {
        case .wait:
            break
        case .drop:
            entry.discard()
        case .showCurrentSession, .uncoverActiveSet, .listen:
            entry.closeCovers()
            moveStage(toward: route)
        }
    }

    /// The card takes a `.listen` request itself once it shows, so only the other routes move it.
    private func moveStage(toward route: SetDictationEntryRoute) {
        switch route {
        case .showCurrentSession:
            navigationAdapter.showCurrent()
        case .uncoverActiveSet:
            endSpokenWriteHold()
            perform(nil) { focusManager.collapseLoggedSetReview() }
        case .wait, .drop, .listen:
            break
        }
    }

    /// True while a request waits for `slot`'s card to listen for its Set.
    func startsHandsFree(_ slot: SetCardSlot) -> Bool {
        guard slot.mode == .logging, case .listen(let setID) = entryRoute else { return false }
        return Self.activeSetID(for: slot.set) == setID
    }

    /// Takes the waiting request and listens for `set` until the athlete stops talking, writing
    /// what was said as a release of the mic would. `shown` reads the card's values when
    /// listening ends, which fill what was left unsaid.
    func listenHandsFree(to set: ExerciseSet, showing shown: () -> SetLogDraft) async -> SetDictation.Outcome? {
        guard let dictation, let session, case .listen(let setID) = entryRoute, Self.activeSetID(for: set) == setID else { return nil }
        _ = entry?.take()
        dictatingSession = session
        let outcome = await dictation.listenUntilQuiet(for: setID) { SpokenSetContext(for: set, showing: shown()) }
        return write(outcome, heardFor: setID, in: session)
    }

    /// Nil while no request waits.
    private var entryRoute: SetDictationEntryRoute? {
        guard entry?.pending != nil else { return nil }
        guard let session else { return .wait }
        guard micIsFreeForAPendingSet else { return .drop }
        guard navigationAdapter.liveEdge(for: session).isAtLiveEdge else { return .showCurrentSession }
        return entryRoute(onLiveEdgeOf: session)
    }

    /// True while the mic is idle and the Current Session still has a Pending Set to log.
    private var micIsFreeForAPendingSet: Bool {
        guard let dictation, dictation.state.listeningSetID == nil, let current = navigationAdapter.currentSession else { return false }
        return SessionSetOrder.firstPendingSet(in: current) != nil
    }

    private func entryRoute(onLiveEdgeOf session: Session) -> SetDictationEntryRoute {
        switch focusManager.visualFocusOwner {
        case .loggedSetReview, .heldAfterSpokenWrite:
            return .uncoverActiveSet
        case .activeSet(let setID) where pendingSet(at: setID, in: session) != nil:
            return .listen(setID)
        case .activeSet, nil:
            return .drop
        }
    }
}
