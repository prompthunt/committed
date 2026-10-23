import Foundation
import Observation
import UserNotifications

/// Receives relative-rank crossing events and decides what (if anything) to surface to the user.
@MainActor
protocol RankChangeNotifying: AnyObject {
    func post(_ events: [RankChangeEvent])
}

/// Posts local macOS notifications for position changes, gated by the opt-in toggle and the
/// system notification authorization. Everything degrades to a no-op when the toggle is off,
/// authorization isn't granted, or `UNUserNotificationCenter` is unavailable (e.g. an unsigned
/// dev build) — so a missing permission never crashes or blocks a refresh.
@MainActor
@Observable
final class NotificationService: RankChangeNotifying {
    /// UserDefaults key shared with the ⋯-menu toggle. Default (absent) reads as `false`.
    static let enabledDefaultsKey = "notifyOnPositionChange"

    // Computed (not stored) so nothing touches UNUserNotificationCenter at init/launch — that
    // call can hang an LSUIElement app host (e.g. the unit-test runner). Resolved lazily only
    // when we actually request authorization or post.
    private var center: UNUserNotificationCenter { .current() }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledDefaultsKey) }

    /// Ask for alert+sound permission. Called when the user first flips the toggle on. Returns
    /// whether permission is granted (false on denial / unavailability) so the caller can reconcile
    /// the toggle state rather than leaving it on with no notifications ever arriving.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ events: [RankChangeEvent]) {
        guard isEnabled, !events.isEmpty else { return }
        Task { await deliver(events) }
    }

    private func deliver(_ events: [RankChangeEvent]) async {
        // Re-check the toggle after the await — the user may have turned it off between the refresh
        // enqueuing this and delivery.
        guard isEnabled else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        if events.count > 3 {
            // Coalesce a flurry into one summary rather than stacking many banners.
            await add(id: "rankchange.summary",
                      title: "\(events.count) position changes",
                      body: "Your standings shifted since the last check.")
        } else {
            for event in events {
                let copy = Self.copy(for: event)
                // Stable per-rival id so a rapid re-fire replaces rather than stacks.
                await add(id: "rankchange.\(event.rivalUsername)", title: copy.title, body: copy.body)
            }
        }
    }

    private func add(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Pure event → (title, body) mapping, split out so it's testable without the notification
    /// center.
    nonisolated static func copy(for event: RankChangeEvent) -> (title: String, body: String) {
        switch event.direction {
        case .iPassedRival:
            // The win — celebrate it.
            return ("🎉 You passed \(event.rivalUsername)!",
                    "You're ahead \(event.myContributions)–\(event.rivalContributions). Keep climbing!")
        case .rivalPassedMe:
            // The nudge — make it a rivalry, not a downer.
            return ("😤 \(event.rivalUsername) passed you",
                    "They're ahead \(event.rivalContributions)–\(event.myContributions). Time to catch up!")
        }
    }
}
