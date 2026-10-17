@preconcurrency import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class LiveActivityController {
    @ObservationIgnored
    private var activityID: String?

    private(set) var isActive = false
    private(set) var areActivitiesEnabled = LiveActivityController.activitiesEnabled
    var lastError: String?

    func refreshAuthorizationStatus() {
        areActivitiesEnabled = Self.activitiesEnabled
        isActive = currentActivity != nil
    }

    private static var activitiesEnabled: Bool {
        #if DEBUG
            if UITestFixture.launch.disablesLiveActivities {
                return false
            }
        #endif
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        state: WorkoutActivityAttributes.ContentState,
        sessionLabel: String,
        staleDate: Date? = nil
    ) async {
        refreshAuthorizationStatus()
        guard areActivitiesEnabled else {
            lastError = "Live Activities are disabled for this device or app."
            return
        }

        await end()

        do {
            let activity = try Activity.request(
                attributes: WorkoutActivityAttributes(sessionLabel: sessionLabel),
                content: ActivityContent(state: state, staleDate: staleDate),
                pushType: nil
            )
            activityID = activity.id
            isActive = true
            lastError = nil
        } catch {
            activityID = nil
            isActive = false
            lastError = "Couldn't start Live Activity: \(error.localizedDescription)"
        }
    }

    func update(state: WorkoutActivityAttributes.ContentState, staleDate: Date? = nil) async {
        guard let activity = currentActivity else {
            activityID = nil
            isActive = false
            lastError = "Start the Live Activity before updating it."
            return
        }

        activityID = activity.id
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
        isActive = true
        lastError = nil
    }

    func end() async {
        let runningActivities = Activity<WorkoutActivityAttributes>.activities
        guard !runningActivities.isEmpty else {
            activityID = nil
            isActive = false
            return
        }

        for activity in runningActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activityID = nil
        isActive = false
    }

    /// Ends the running activity on `state`, which stays on the Lock Screen until `date`. The
    /// system removes it then even if this process is asleep by then.
    func end(showing state: WorkoutActivityAttributes.ContentState, dismissingAt date: Date) async {
        guard let activity = currentActivity else {
            activityID = nil
            isActive = false
            return
        }
        await activity.end(ActivityContent(state: state, staleDate: date), dismissalPolicy: .after(date))
        activityID = nil
        isActive = false
    }

    /// An activity that has ended but is still on the Lock Screen cannot be updated, so only a
    /// live one counts.
    private var currentActivity: Activity<WorkoutActivityAttributes>? {
        let live = Activity<WorkoutActivityAttributes>.activities.filter { $0.activityState == .active }
        if let activityID, let own = live.first(where: { $0.id == activityID }) {
            return own
        }
        return live.first
    }
}
