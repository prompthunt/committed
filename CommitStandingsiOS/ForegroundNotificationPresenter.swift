import UserNotifications

/// iOS keeps a notification out of sight when its app is frontmost unless the app asks.
/// Committed finds crossings in foreground refreshes, so it asks to show them as banners.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// The center holds its delegate weakly; this keeps it alive.
    static let shared = ForegroundNotificationPresenter()

    /// Call once at launch (not under the unit-test host).
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
