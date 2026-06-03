@preconcurrency import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class LiveActivityController {
    @ObservationIgnored
    private var activityID: String?

    private(set) var isActive = false
    private(set) var areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    var lastError: String?

    func refreshAuthorizationStatus() {
        areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        isActive = currentActivity != nil
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

    private var currentActivity: Activity<WorkoutActivityAttributes>? {
        if let activityID {
            return Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == activityID })
                ?? Activity<WorkoutActivityAttributes>.activities.first
        }

        return Activity<WorkoutActivityAttributes>.activities.first
    }
}
