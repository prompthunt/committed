import UserNotifications

/// iOS hides a notification that arrives while its app is open unless the app says otherwise.
/// Leaderboard Notifications mostly come from foreground refreshes, so show them as a banner
/// even while Committed is open. The Mac app doesn't need this.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundNotificationPresenter()

    /// The notification center keeps its delegate weakly; `shared` keeps this one alive.
    @MainActor
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
