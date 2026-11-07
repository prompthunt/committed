import Testing
import Foundation
@testable import CommitStandings

/// The Leaderboard Notifications switch (Mac ⋯ menu, iPhone Settings): turning it on asks for
/// permission and stays on only if permission is granted.
@MainActor
struct NotificationToggleTests {
    private func defaults() throws -> UserDefaults {
        let suite = "notification-toggle-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func turningOnStaysOnWhenPermissionIsGranted() async throws {
        let defaults = try defaults()
        var prompts = 0
        let service = NotificationService(defaults: defaults, authorize: { prompts += 1; return true })
        #expect(!service.isEnabled)
        #expect(await service.setEnabled(true))
        #expect(service.isEnabled)
        #expect(defaults.bool(forKey: NotificationService.enabledDefaultsKey))
        #expect(prompts == 1)
    }

    @Test func turningOnSwitchesBackOffWhenPermissionIsDenied() async throws {
        let defaults = try defaults()
        let service = NotificationService(defaults: defaults, authorize: { false })
        #expect(await service.setEnabled(true) == false)
        #expect(!service.isEnabled)
    }

    @Test func turningOffNeverAsksForPermission() async throws {
        let defaults = try defaults()
        defaults.set(true, forKey: NotificationService.enabledDefaultsKey)
        var prompts = 0
        let service = NotificationService(defaults: defaults, authorize: { prompts += 1; return true })
        #expect(await service.setEnabled(false) == false)
        #expect(!service.isEnabled)
        #expect(prompts == 0)
    }
}
