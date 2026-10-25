import Foundation

@MainActor
final class LiveActivityProductionAdapter: SessionLiveActivityAdapter {
    /// How long a headless Dictation's result stays on the Lock Screen when no rest took over.
    static let dictationResultLifetime: TimeInterval = 3 * 60

    private let controller: LiveActivityController
    /// Whose the running Live Activity is; `LiveActivityReadbackPlan` decides what that means.
    private var owner = LiveActivityOwner.nobody
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
    /// other readback goes where `LiveActivityReadbackPlan` says: over a running rest, or on an
    /// activity of its own that the result ends with a dismissal `dictationResultLifetime` on.
    @discardableResult
    func show(_ content: LiveActivityDictationContent, sessionLabel: String) async -> Bool {
        let readback = LiveActivityDictation(content.readback)
        switch content.subject {
        case .rest(let rest):
            startOrUpdate(restContent: rest, dictation: readback, sessionLabel: sessionLabel)
            await startUpdateTask?.value
            return controller.isActive
        case .set(let set):
            return await show(
                readback,
                else: WorkoutActivityAttributes.ContentState(setContent: set, dictation: readback),
                sessionLabel: sessionLabel,
                ridingRestIf: content.rides
            )
        }
    }

    /// A press with no Set to listen for reads back like a result, over whatever rest runs.
    func show(_ noSet: LiveActivityNoSetReadback) async -> Bool {
        let readback = LiveActivityDictation(noSet)
        let alone = WorkoutActivityAttributes.ContentState(noSetToLog: readback)
        switch noSet {
        case .noSetLeft(let session): return await show(readback, else: alone, sessionLabel: session, ridingRestIf: { _ in true })
        case .noCurrentSession: return await show(readback, else: alone, sessionLabel: "", ridingRestIf: { _ in true })
        }
    }

    func withdrawReadback() async {
        controller.refreshAuthorizationStatus()
        switch LiveActivityReadbackWithdrawal.plan(owner: owner, activityIsUp: controller.isActive) {
        case .restoreRest(let rest):
            await controller.update(
                state: WorkoutActivityAttributes.ContentState(restContent: rest, dictation: nil),
                staleDate: LiveActivityInvalidationPolicy.postRestCapEndDate(for: rest)
            )
        case .end:
            await controller.end()
            owner = .nobody
        case .nothing:
            break
        }
    }

    /// True when a Live Activity shows the readback once the steps are done, an ended one
    /// included, which stays on the Lock Screen to be read.
    @discardableResult
    private func show(
        _ readback: LiveActivityDictation,
        else alone: WorkoutActivityAttributes.ContentState,
        sessionLabel: String,
        ridingRestIf rides: (LiveActivityRestContent) -> Bool
    ) async -> Bool {
        controller.refreshAuthorizationStatus()
        takeOverRestLeftRunning()
        let plan = LiveActivityReadbackPlan.plan(
            isFinal: !readback.isListening,
            owner: owner,
            activityIsUp: controller.isActive,
            rides: rides
        )
        let state: WorkoutActivityAttributes.ContentState =
            switch plan.canvas {
            case .overRest(let rest): WorkoutActivityAttributes.ContentState(restContent: rest, dictation: readback)
            case .alone: alone
            }
        if plan.owner != owner {
            clearLifecycleTasks()
        }
        owner = plan.owner
        var shows = controller.isActive
        for step in plan.steps {
            switch step {
            case .start:
                await controller.start(state: state, sessionLabel: sessionLabel, staleDate: plan.canvas.staleDate)
                shows = controller.isActive
                guard shows else {
                    owner = .nobody
                    return false
                }
            case .update:
                await controller.update(state: state, staleDate: plan.canvas.staleDate)
                shows = controller.isActive
            case .endShowing:
                await controller.end(showing: state, dismissingAt: Date().addingTimeInterval(Self.dictationResultLifetime))
            }
        }
        return shows
    }

    /// A rest an earlier process started may still count down on the Lock Screen. It is read back
    /// off the activity so a readback rides it and its lifecycle runs here; once its post-rest
    /// cap has passed it is nobody's, and the readback takes the activity.
    private func takeOverRestLeftRunning() {
        guard
            owner == .nobody, controller.isActive,
            let state = controller.currentState,
            let rest = LiveActivityRestContent(leftRunning: state),
            !LiveActivityInvalidationPolicy.shouldEndReadyReminder(for: rest, at: Date())
        else { return }
        owner = .rest(rest)
        scheduleLifecycleTasks(for: rest)
    }
}
