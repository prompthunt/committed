import Foundation

/// The Sample board's data layer: `CommittedServices` on built-in people and counts, held in
/// memory, with nothing sent over the network. Every view and rule above it is real
/// (`RefreshCoordinator`, `Ranking`, the roster, Leaderboard Notifications), so the Sample board
/// and the App Store screenshots (the Debug `-ScreenshotFixture`) show the app as it works.
///
/// - No GitHub API: the contributions client, People and the device flow are local. The
///   identity call (`/user`) is answered in process as Sam Rivera; anything else fails as if
///   offline.
/// - No relay and no avatars: those belong to `AppModel`, which must pair sample services with
///   `NoLiveRankRelay` and network avatars off (`loadsGitHubAvatars`).
/// - Nothing reaches the real saved board: the standings, people, hidden people and token all
///   live in memory. Leaderboard Notifications keep their real on/off setting.
///
/// `make` is inert: the board loads when something refreshes it (`AppModel.sceneDidBecomeActive`,
/// pull to refresh). Today moves between the first two fetches: Sam Rivera passes Devon K.
@MainActor
enum SampleServices {
    /// "You" on the Sample board.
    nonisolated static let owner = "sam-rivera"
    nonisolated static let ownerName = "Sam Rivera"
    /// Everyone on the Sample board, you included, in board order on Today before it moves.
    nonisolated static let people = ["maya-chen", "priya-s", "devon-k", owner, "lee-park"]
    /// Listed in People but never loads, to show the missing-data placeholder. Screenshot fixture
    /// only; off on the Sample board.
    nonisolated static let failingCompetitor = "jordan-a"

    struct Options {
        /// That many more followed people (`guest-01`, …) below everyone else, for a board long
        /// enough to scroll.
        var extraPeople = 0
        /// Adds `failingCompetitor` to the Acme organization.
        var includesFailingCompetitor = false
        /// Organizations that won't list their members for Committed, as People shows them.
        var restrictedOrganizations: [String]?
    }

    static func make(_ options: Options = Options(), now: @escaping @Sendable () -> Date = { Date() })
        -> CommittedServices {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineGitHub.self]
        let session = URLSession(configuration: config)
        let guests = (0..<options.extraPeople).map { String(format: "guest-%02d", $0 + 1) }
        let organization = ["priya-s", "lee-park"] + (options.includesFailingCompetitor ? [failingCompetitor] : [])
        let restricted = options.restrictedOrganizations
        return CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "sample"),
            contributions: SampleContributions(),
            // Even a stray Connect GitHub on this graph stays on the phone.
            gitHubAuth: GitHubAuth(clientID: "sample", session: session),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: owner, sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["maya-chen", "devon-k"] + guests),
                    GitHubRosterSource(id: "org", title: "Acme", members: organization),
                ], updatedAt: now().addingTimeInterval(-240), restrictedOrganizations: restricted)
            },
            now: now
        )
    }

    /// Fixed Contributions per Window. Each person's first fetch sets today's baseline; from the
    /// second on, Sam Rivera has 7 today and passes Devon K. Guests have fewer than anyone else.
    private actor SampleContributions: ContributionsFetching {
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
            if username.hasPrefix("guest-"), let number = Int(username.dropFirst(6)) {
                return .success(StandingCounts(contributions: max(0, 40 - number)))
            }
            guard let count = counts[username]?[window] else { return .failure(.network("offline")) }
            return .success(StandingCounts(contributions: count))
        }
    }

    /// Answers GitHub's `/user` with the sample profile, in process, and fails everything else as
    /// if offline.
    private final class OfflineGitHub: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url, url.host == "api.github.com", url.path == "/user",
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            let body = Data(#"{"login":"\#(SampleServices.owner)","name":"\#(SampleServices.ownerName)"}"#.utf8)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
