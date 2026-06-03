import Foundation

@MainActor
final class LiveActivityProductionAdapter: SessionLiveActivityAdapter {
    private let controller: LiveActivityController
    private var currentRestContent: LiveActivityRestContent?
    private var startUpdateTask: Task<Void, Never>?
    private var startUpdateID: UUID?
    private var readyUpdateTask: Task<Void, Never>?
    private var capEndTask: Task<Void, Never>?

    init(controller: LiveActivityController = LiveActivityController()) {
        self.controller = controller
    }

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        currentRestContent = restContent
        startUpdateTask?.cancel()
        let operationID = UUID()
        startUpdateID = operationID
        scheduleLifecycleTasks(for: restContent)
        let state = WorkoutActivityAttributes.ContentState(restContent: restContent)
        let staleDate = LiveActivityInvalidationPolicy.postRestCapEndDate(for: restContent)

        startUpdateTask = Task { @MainActor [weak self, controller] in
            guard self?.isCurrentOperation(operationID, content: restContent) == true else { return }

            controller.refreshAuthorizationStatus()
            if controller.isActive {
                await controller.update(state: state, staleDate: staleDate)
                guard self?.isCurrentOperation(operationID, content: restContent) == true else {
                    await self?.endIfOperationWasInvalidated()
                    return
                }
                if controller.isActive { return }
            }

            await controller.start(state: state, sessionLabel: sessionLabel, staleDate: staleDate)
            guard self?.isCurrentOperation(operationID, content: restContent) == true else {
                await self?.endIfOperationWasInvalidated()
                return
            }
        }
    }

    func end() {
        clearLifecycleTasks()
        currentRestContent = nil
        startUpdateTask?.cancel()
        startUpdateTask = nil
        startUpdateID = nil
        Task { @MainActor [controller] in
            await controller.end()
        }
    }

    func endIfInvalidated(displayedSession: Session?, currentSession: Session?) {
        guard let currentRestContent else { return }
        guard !LiveActivityInvalidationPolicy.shouldEndReadyReminder(for: currentRestContent, at: Date()) else {
            end()
            return
        }
        guard
            !LiveActivityInvalidationPolicy.shouldEnd(
                currentRestContent,
                displayedSession: displayedSession,
                currentSession: currentSession
            )
        else {
            end()
            return
        }
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
                state: WorkoutActivityAttributes.ContentState(restContent: content),
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
