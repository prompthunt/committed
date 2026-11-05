import Testing
import Foundation
@testable import CommitStandingsiOS

/// Hiding and showing people from the People tab, and Disconnect GitHub from Settings.
extension FakeGitHubSuites {
@Suite
@MainActor
struct PeopleVisibilityTests {

    /// Saved state that outlives one `AppModel`, like UserDefaults and the Keychain do.
    private struct Device {
        let credentials = InMemoryGitHubCredentialStore(token: "gho_test")
        let competitors = InMemoryCompetitorPersistence()
        let snapshot = InMemoryStandingsSnapshotPersistence()
        let hidden = InMemoryHiddenPeoplePersistence()
        let contributions = StubContributions(["me": 5, "alice": 9, "bob": 3])

        @MainActor func launch() -> AppModel {
            var dependencies = AppDependencies.testing(contributions: contributions, credentials: credentials)
            dependencies.competitorPersistence = competitors
            dependencies.snapshotPersistence = snapshot
            dependencies.hiddenPeoplePersistence = hidden
            return AppModel(dependencies)
        }
    }

    private func boardNames(_ app: AppModel) -> [String] {
        Board(store: app.store, refresh: app.refresh).rows.map(\.competitor.username)
    }

    private func loadedApp(_ device: Device) async -> AppModel {
        FakeGitHub.reset(.init(login: "me", following: ["alice"], organizations: ["acme": ["bob"]]))
        let app = device.launch()
        await app.refresh.refreshAll(reason: .manual)
        return app
    }

    @Test func hidingSomeoneTakesThemOffTheBoardRightAwayButKeepsThemInPeople() async {
        let app = await loadedApp(Device())
        #expect(boardNames(app) == ["alice", "me", "bob"])

        await app.setHidden(true, username: "alice")

        #expect(boardNames(app) == ["me", "bob"])
        #expect(Board(store: app.store, refresh: app.refresh).summary?.rank == 1)
        let people = PeopleDirectory.people(app.store.competitors, roster: app.roster.snapshot, source: .all, query: "")
        #expect(people.map(\.username) == ["alice", "bob", "me"])
        #expect(app.store.isHidden("alice"))
    }

    @Test func showingSomeoneAgainRestoresThemWithFreshNumbers() async {
        let device = Device()
        let app = await loadedApp(device)
        await app.setHidden(true, username: "alice")
        await device.contributions.set("alice", 11)

        await app.setHidden(false, username: "alice")

        #expect(boardNames(app) == ["alice", "me", "bob"])
        #expect(app.store.standing(for: "alice", window: .daily)?.contributions == 11)
        #expect(await device.contributions.calls.last?.username == "alice")
    }

    @Test func youCannotHideYourself() async {
        let app = await loadedApp(Device())

        await app.setHidden(true, username: "me")

        #expect(!app.store.isHidden("me"))
        #expect(boardNames(app) == ["alice", "me", "bob"])
    }

    @Test func hiddenPeopleStayHiddenAfterRelaunch() async {
        let device = Device()
        let app = await loadedApp(device)
        await app.setHidden(true, username: "alice")

        let relaunched = device.launch()

        #expect(relaunched.store.isHidden("alice"))
        #expect(!boardNames(relaunched).contains("alice"))
    }

    @Test func disconnectDeletesTheTokenAndReturnsToConnect() async {
        let device = Device()
        let app = await loadedApp(device)

        app.disconnect()

        #expect(!app.auth.isSignedIn)
        #expect(app.auth.phase == .signedOut)
        #expect(device.credentials.read() == nil)
        #expect(app.store.competitors.isEmpty, "the account's cached people and counts are cleared")
    }

    @Test func hiddenPeopleStayHiddenAfterDisconnectAndReconnect() async {
        let device = Device()
        let app = await loadedApp(device)
        await app.setHidden(true, username: "alice")

        app.disconnect()
        FakeGitHub.reset(.init(polls: [.token("gho_again")], login: "me", following: ["alice"],
                               organizations: ["acme": ["bob"]]))
        await app.auth.signIn()

        #expect(app.auth.isSignedIn)
        #expect(app.store.isHidden("alice"))
        #expect(boardNames(app) == ["me", "bob"])
    }
}
}
