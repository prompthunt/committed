#if DEBUG
import Foundation

/// Debug builds only: launch with `-ScreenshotFixture` to run the real app on a fixed, offline
/// board (no GitHub account, no network) for screenshots and visual checks:
///
///     xcrun simctl launch <udid> com.addisonk.CommitStandings.iOS -ScreenshotFixture
///
/// Everything above the data layer is real: `CommittedServices`, `RefreshCoordinator`, `Ranking`,
/// and every view. Counts move between the first two refreshes so Today shows movement chevrons.
/// One person always fails to load, to show the missing-data placeholder.
@MainActor
enum ScreenshotFixture {
    static let launchArgument = "-ScreenshotFixture"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// With `-LiveRankPushUpdates`, Live rank starts with a push token, so `xcrun simctl push`
    /// payloads can update it (see the spec #39 notes, 43-live-rank.md).
    static var liveRankRelay: any LiveRankRegistrar {
        ProcessInfo.processInfo.arguments.contains("-LiveRankPushUpdates") ? PushUpdatesRelay() : NoLiveRankRelay()
    }

    /// No relay, but activities take push updates like they will with one.
    private final class PushUpdatesRelay: LiveRankRegistrar {
        var pushUpdates: LiveRankPushUpdates { .token }
        func liveRankDidChange(_ configuration: LiveRankConfiguration?) async {}
    }

    static func services() -> CommittedServices {
        // Keep GitHub requests offline. Avatars are off too (`loadsGitHubAvatars`), so no real
        // account's avatar appears for these made-up usernames.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineProtocol.self]
        let session = URLSession(configuration: config)
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "fixture"),
            contributions: FixtureContributions(),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "sam-rivera", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["maya-chen", "devon-k"]),
                    GitHubRosterSource(id: "org", title: "Acme", members: ["priya-s", "lee-park", "jordan-a"]),
                ], updatedAt: Date().addingTimeInterval(-240))
            }
        )
        Task {
            await services.auth.refreshIdentity()
            // Two refreshes on the same day: the first sets today's baseline, the second moves.
            await services.refresh.refreshAll(reason: .manual)
            await services.refresh.refreshAll(reason: .timer)
        }
        return services
    }

    /// Round 1 sets today's baseline; later rounds have sam-rivera passing devon-k.
    private actor FixtureContributions: ContributionsFetching {
        private var rounds: [String: Int] = [:]

        func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
            async -> Result<StandingCounts, ContributionsError> {
            let round = rounds[username, default: 0]
            rounds[username] = round + 1
            let counts: [String: [ContributionWindow: Int]] = [
                "maya-chen": [.daily: 12, .weekly: 61, .monthly: 240],
                "priya-s": [.daily: 9, .weekly: 44, .monthly: 198],
                "sam-rivera": [.daily: round == 0 ? 5 : 7, .weekly: 38, .monthly: 171],
                "devon-k": [.daily: 6, .weekly: 52, .monthly: 160],
                "lee-park": [.daily: 0, .weekly: 11, .monthly: 57],
            ]
            guard let count = counts[username]?[window] else { return .failure(.network("offline")) }
            return .success(StandingCounts(contributions: count))
        }
    }

    /// Answers `/user` with a fixed profile and fails everything else as if offline.
    private final class OfflineProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard request.url?.host == "api.github.com", request.url?.path == "/user" else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            let body = Data(#"{"login":"sam-rivera","name":"Sam Rivera"}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
#endif
