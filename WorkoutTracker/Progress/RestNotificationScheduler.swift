import Foundation

#if canImport(UserNotifications)
    import UserNotifications
#endif

@MainActor
protocol RestNotificationScheduling: AnyObject {
    func requestAuthorizationIfNeeded()
    func schedule(deadline: Date)
    func cancel()
}

#if canImport(UserNotifications)
    enum RestNotificationForegroundPolicy {
        static let identifier = "workout-tracker.rest.deadline"

        static func presentationOptions(for identifier: String) -> UNNotificationPresentationOptions {
            identifier == Self.identifier ? [] : [.banner, .sound]
        }
    }

    @MainActor
    final class RestNotificationCenterScheduler: NSObject, RestNotificationScheduling {
        static let shared = RestNotificationCenterScheduler()

        private static let authorizationRequestedKey = "restNotificationAuthorizationRequested"
        private let center: UNUserNotificationCenter
        private let defaults: UserDefaults
        private let now: () -> Date
        private let foregroundDelegate = RestNotificationForegroundDelegate()

        init(
            center: UNUserNotificationCenter = .current(),
            defaults: UserDefaults = .standard,
            now: @escaping () -> Date = Date.init
        ) {
            self.center = center
            self.defaults = defaults
            self.now = now
        }

        func installForegroundDelegate() {
            center.delegate = foregroundDelegate
        }

        func requestAuthorizationIfNeeded() {
            guard !defaults.bool(forKey: Self.authorizationRequestedKey) else { return }
            defaults.set(true, forKey: Self.authorizationRequestedKey)
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        func schedule(deadline: Date) {
            let content = UNMutableNotificationContent()
            content.title = "Rest's up"
            content.sound = .default

            let timeInterval = max(1, deadline.timeIntervalSince(now()))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            let request = UNNotificationRequest(
                identifier: RestNotificationForegroundPolicy.identifier,
                content: content,
                trigger: trigger
            )
            center.add(request) { _ in }
        }

        func cancel() {
            center.removePendingNotificationRequests(withIdentifiers: [RestNotificationForegroundPolicy.identifier])
        }
    }

    final class RestNotificationForegroundDelegate: NSObject, UNUserNotificationCenterDelegate {
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            RestNotificationForegroundPolicy.presentationOptions(for: notification.request.identifier)
        }
    }
#endif
