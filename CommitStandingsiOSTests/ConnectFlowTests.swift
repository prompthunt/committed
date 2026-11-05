import Testing
import Foundation
@testable import CommitStandingsiOS

/// Connect GitHub on iPhone, end to end through the real device-flow, account, and roster
/// clients, with github.com faked.
extension FakeGitHubSuites {
@Suite
@MainActor
struct ConnectFlowTests {

    @Test func connectShowsTheCodeKeepsPollingThenLandsOnTheRankedBoard() async throws {
        FakeGitHub.reset(.init(
            polls: [.pending, .slowDown, .pending, .token("gho_test")],
            login: "me",
            following: ["alice"],
            organizations: ["acme": ["bob", "me"]]
        ))
        let credentials = InMemoryGitHubCredentialStore()
        let contributions = StubContributions(["me": 5, "alice": 9, "bob": 5])
        let app = AppModel(.testing(contributions: contributions, credentials: credentials))
        #expect(app.auth.phase == .signedOut)

        var phases: [AuthModel.Phase] = []
        let observer = Task { @MainActor in
            while !Task.isCancelled {
                if phases.last != app.auth.phase { phases.append(app.auth.phase) }
                await Task.yield()
            }
        }
        await app.auth.signIn()
        observer.cancel()

        #expect(phases.contains(.connecting(userCode: "WDJB-MJHT", verificationURL: "https://github.com/login/device")))
        #expect(FakeGitHub.requestedScope == "read:org read:user")
        #expect(FakeGitHub.pollCount == 4)
        #expect(app.auth.isSignedIn)
        #expect(app.auth.username == "me")
        #expect(credentials.read() == "gho_test")

        let board = Board(store: app.store, refresh: app.refresh)
        #expect(board.rows.map(\.competitor.username) == ["alice", "me", "bob"])
        #expect(board.rows.map(\.rank) == [1, 2, 3])
        #expect(board.rows.map { $0.standing?.contributions } == [9, 5, 5])
    }

    @Test func aCodeThatExpiresWhileSuspendedIsReportedOnReturn() async {
        FakeGitHub.reset(.init(polls: [.pending, .pending, .pending]))
        let clock = TestClock()
        // Each wait between polls "suspends" the app for six minutes; the 15-minute code
        // runs out during the third.
        let app = AppModel(.testing(
            contributions: StubContributions(),
            clock: clock,
            authSleep: { _ in clock.advance(360) }
        ))

        await app.auth.signIn()

        #expect(app.auth.phase == .signedOut)
        #expect(app.auth.errorMessage == "The code expired. Try again.")
    }

    @Test func declinedAccessExplainsHowToRetry() async {
        FakeGitHub.reset(.init(polls: [.pending, .denied]))
        let credentials = InMemoryGitHubCredentialStore()
        let app = AppModel(.testing(contributions: StubContributions(), credentials: credentials))

        await app.auth.signIn()

        #expect(app.auth.phase == .signedOut)
        #expect(app.auth.errorMessage == "The GitHub connection was declined.")
        #expect(credentials.read() == nil)
    }
}
}
