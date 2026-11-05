import Testing
import Foundation
@testable import CommitStandingsiOS

/// Leaderboard Notifications on iPhone: crossings found by foreground refreshes are posted with
/// the Mac's copy, only after you turn them on and allow them.
extension FakeGitHubSuites {
@Suite
@MainActor
struct LeaderboardNotificationTests {

    private func app(center: FakeNotificationCenter, contributions: StubContributions) -> AppModel {
        FakeGitHub.reset(.init(login: "me", following: ["alice"]))
        var dependencies = AppDependencies.testing(
            contributions: contributions,
            credentials: InMemoryGitHubCredentialStore(token: "gho_test")
        )
        dependencies.notificationCenter = center
        return AppModel(dependencies)
    }

    /// `post` delivers on its own task; give it a moment.
    private func waitForDelivery(_ center: FakeNotificationCenter) async {
        for _ in 0..<100 where center.delivered.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func someonePassingYouBetweenRefreshesPostsTheExistingCopy() async {
        let center = FakeNotificationCenter()
        let contributions = StubContributions(["me": 5, "alice": 3])
        let app = app(center: center, contributions: contributions)
        #expect(await app.notifications.setEnabled(true))
        await app.refresh.refreshAll(reason: .manual)

        await contributions.set("alice", 8)
        await app.refresh.refreshAll(reason: .timer)
        await waitForDelivery(center)

        #expect(center.delivered.map(\.title) == ["😤 alice passed you"])
        #expect(center.delivered.first?.body == "They're ahead 8–5. Time to catch up!")
    }

    @Test func passingSomeonePostsTheWinCopy() async {
        let center = FakeNotificationCenter()
        let contributions = StubContributions(["me": 2, "alice": 4])
        let app = app(center: center, contributions: contributions)
        await app.notifications.setEnabled(true)
        await app.refresh.refreshAll(reason: .manual)

        await contributions.set("me", 6)
        await app.refresh.refreshAll(reason: .becameActive)
        await waitForDelivery(center)

        #expect(center.delivered.map(\.title) == ["🎉 You passed alice!"])
    }

    @Test func nothingIsPostedWhileNotificationsAreOff() async throws {
        let center = FakeNotificationCenter()
        let contributions = StubContributions(["me": 5, "alice": 3])
        let app = app(center: center, contributions: contributions)
        await app.refresh.refreshAll(reason: .manual)

        await contributions.set("alice", 8)
        await app.refresh.refreshAll(reason: .timer)
        try await Task.sleep(for: .milliseconds(100))

        #expect(center.delivered.isEmpty)
    }

    @Test func turningNotificationsOnAsksForPermissionAndStaysOffWhenDenied() async {
        let center = FakeNotificationCenter(grantsPermission: false)
        let app = app(center: center, contributions: StubContributions())

        let isOn = await app.notifications.setEnabled(true)

        #expect(center.authorizationRequests == 1)
        #expect(!isOn)
        #expect(!app.notifications.isEnabled)
    }
}
}
