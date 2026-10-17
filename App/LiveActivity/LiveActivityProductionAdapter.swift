import Foundation

@MainActor
final class LiveActivityProductionAdapter: SessionLiveActivityAdapter {
    /// Whose the running Live Activity is, which decides what ends it.
    private enum Owner: Equatable {
        case nobody
        /// The stage's rest after a logged Set: its dates run the lifecycle.
        case rest(LiveActivityRestContent)
        /// A headless Dictation's Set, with no rest: it ends on the Dictation's result, staying on
        /// the Lock Screen `dictationResultLifetime` for the athlete to read.
        case dictation
    }

    /// How long a headless Dictation's result stays on the Lock Screen when no rest took over.
    static let dictationResultLifetime: TimeInterval = 3 * 60

    private let controller: LiveActivityController
    private var owner = Owner.nobody
    private var startUpdateTask: Task<Void, Never>?
    private var startUpdateID: UUID?
    private var readyUpdateTask: Task<Void, Never>?
    private var capEndTask: Task<Void, Never>?

    init(controller: LiveActivityController = LiveActivityController()) {
        self.controller = controller
    }

    private var currentRestContent: LiveActivityRestContent? {
        guard case .rest(let content) = owner else { return nil }
        return content
    }

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        startOrUpdate(restContent: restContent, dictation: nil, sessionLabel: sessionLabel)
    }

    private func startOrUpdate(restContent: LiveActivityRestContent, dictation: LiveActivityDictation?, sessionLabel: String) {
        owner = .rest(restContent)
        startUpdateTask?.cancel()
        let operationID = UUID()
        startUpdateID = operationID
        scheduleLifecycleTasks(for: restContent)
        let state = WorkoutActivityAttributes.ContentState(restContent: restContent, dictation: dictation)
        let staleDate = LiveActivityInvalidationPolicy.postRestCapEndDate(for: restContent)

        startUpdateTask = Task { @MainActor [weak self, controller] in
            guard self?.isCurrentOperation(operationID, content: restContent) ?? false else { return }

            controller.refreshAuthorizationStatus()
            if controller.isActive {
                await controller.update(state: state, staleDate: staleDate)
                guard self?.isCurrentOperation(operationID, content: restContent) ?? false else {
                    await self?.endIfOperationWasInvalidated()
                    return
                }
                if controller.isActive { return }
            }

            await controller.start(state: state, sessionLabel: sessionLabel, staleDate: staleDate)
            guard self?.isCurrentOperation(operationID, content: restContent) ?? false else {
                await self?.endIfOperationWasInvalidated()
                return
            }
        }
    }

    func end() {
        clearLifecycleTasks()
        owner = .nobody
        startUpdateTask?.cancel()
        startUpdateTask = nil
        startUpdateID = nil
        // Awaiting it would make the next start wait for this end, which reorders teardown (#699).
        // swiftlint:disable:next unstructured_task_is_held
        Task { @MainActor [controller] in
            await controller.end()
        }
    }

    func endIfInvalidated(at liveEdge: LiveEdge) {
        guard let currentRestContent else { return }
        let isInvalidated =
            LiveActivityInvalidationPolicy.shouldEndReadyReminder(for: currentRestContent, at: Date())
            || LiveActivityInvalidationPolicy.shouldEnd(currentRestContent, at: liveEdge)
        guard isInvalidated else { return }
        end()
    }

    func endIfReadyCapExpired(at date: Date = Date()) {
        guard
            let currentRestContent,
            LiveActivityInvalidationPolicy.shouldEndReadyReminder(for: currentRestContent, at: date)
        else {
            return
        }
        end()
    }

    private func scheduleLifecycleTasks(for content: LiveActivityRestContent) {
        clearLifecycleTasks()
        readyUpdateTask = Task { @MainActor [weak self] in
            await Self.sleep(until: content.restEndDate)
            guard !Task.isCancelled, self?.currentRestContent == content else { return }
            await self?.controller.update(
                state: WorkoutActivityAttributes.ContentState(restContent: content, dictation: nil),
                staleDate: LiveActivityInvalidationPolicy.postRestCapEndDate(for: content)
            )
        }
        capEndTask = Task { @MainActor [weak self] in
            await Self.sleep(until: LiveActivityInvalidationPolicy.postRestCapEndDate(for: content))
            guard !Task.isCancelled, self?.currentRestContent == content else { return }
            self?.end()
        }
    }

    private func clearLifecycleTasks() {
        readyUpdateTask?.cancel()
        readyUpdateTask = nil
        capEndTask?.cancel()
        capEndTask = nil
    }

    private func isCurrentOperation(_ operationID: UUID, content: LiveActivityRestContent) -> Bool {
        !Task.isCancelled && startUpdateID == operationID && currentRestContent == content
    }

    private func endIfOperationWasInvalidated() async {
        guard startUpdateID == nil else { return }
        await controller.end()
    }

    private static func sleep(until date: Date) async {
        let seconds = max(date.timeIntervalSinceNow, 0)
        try? await Task.sleep(for: .seconds(seconds))
    }
}

extension LiveActivityProductionAdapter: DictationLiveActivityAdapter {
    /// A logged Set's rest becomes the stage's rest, readback and all, and runs its lifecycle. Any
    /// other readback rides on a running rest, keeping the countdown, or on an activity started for
    /// the Set, which the result ends with a dismissal `dictationResultLifetime` on.
    func show(_ content: LiveActivityDictationContent, sessionLabel: String) async {
        let readback = LiveActivityDictation(content.readback)
        switch content.subject {
        case .rest(let rest):
            startOrUpdate(restContent: rest, dictation: readback, sessionLabel: sessionLabel)
            await startUpdateTask?.value
        case .set(let set):
            await show(
                readback,
                else: WorkoutActivityAttributes.ContentState(setContent: set, dictation: readback),
                sessionLabel: sessionLabel,
                ridingRestIf: content.rides
            )
        }
    }

    /// A press with no Set to listen for reads back like a result, so it ends what it started.
    func show(_ noSet: LiveActivityNoSetReadback) async {
        let readback = LiveActivityDictation(noSet)
        let alone = WorkoutActivityAttributes.ContentState(noSetToLog: readback)
        switch noSet {
        case .noSetLeft(let session): await show(readback, else: alone, sessionLabel: session)
        case .noCurrentSession: await show(readback, else: alone, sessionLabel: "")
        }
    }

    func withdrawReadback() async {
        switch owner {
        case .rest(let rest) where controller.isActive:
            await controller.update(
                state: WorkoutActivityAttributes.ContentState(restContent: rest, dictation: nil),
                staleDate: LiveActivityInvalidationPolicy.postRestCapEndDate(for: rest)
            )
        case .rest:
            break
        case .dictation, .nobody:
            await controller.end()
            owner = .nobody
        }
    }

    /// `readback` over the running rest, keeping its countdown, else over `alone`. A rest the
    /// readback may not ride is over, so the readback takes its activity and ends it as its own.
    private func show(
        _ readback: LiveActivityDictation,
        else alone: WorkoutActivityAttributes.ContentState,
        sessionLabel: String,
        ridingRestIf rides: (LiveActivityRestContent) -> Bool = { _ in true }
    ) async {
        controller.refreshAuthorizationStatus()
        var state = alone
        if let currentRestContent, controller.isActive {
            if rides(currentRestContent) {
                state = WorkoutActivityAttributes.ContentState(restContent: currentRestContent, dictation: readback)
            } else {
                clearLifecycleTasks()
                owner = .dictation
            }
        }
        await show(state, sessionLabel: sessionLabel, isFinal: !readback.isListening)
    }

    private func show(_ state: WorkoutActivityAttributes.ContentState, sessionLabel: String, isFinal: Bool) async {
        if !controller.isActive {
            await controller.start(state: state, sessionLabel: sessionLabel, staleDate: nil)
            owner = .dictation
        } else if owner != .dictation || !isFinal {
            await controller.update(state: state, staleDate: nil)
        }
        guard isFinal, owner == .dictation else { return }
        await controller.end(showing: state, dismissingAt: Date().addingTimeInterval(Self.dictationResultLifetime))
        owner = .nobody
    }
}
