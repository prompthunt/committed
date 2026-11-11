import Foundation

/// The Sample board's data layer: `CommittedServices` on built-in people and counts, held in
/// memory, with nothing sent over the network. Every view and rule above it is real
/// (`RefreshCoordinator`, `Ranking`, the roster, Leaderboard Notifications), so the Sample board
/// and the App Store screenshots (the Debug `-ScreenshotFixture`) show the app as it works.
///
/// - No GitHub API: the contributions client, People and the device flow are local. The
///   identity call (`/user`) is answered in process as Ari Linden; anything else fails as if
///   offline.
/// - No relay and no avatars: those belong to `AppModel`, which must pair sample services with
///   `NoLiveRankRelay` and network avatars off (`loadsGitHubAvatars`).
/// - Nothing reaches the real saved board: the standings, people, hidden people and token all
///   live in memory. Leaderboard Notifications keep their real on/off setting.
///
/// `make` is inert: the board loads when something refreshes it (`AppModel.sceneDidBecomeActive`,
/// pull to refresh). Today moves between the first two fetches: Ari Linden passes Ezra Q.
@MainActor
enum SampleServices {
    /// "You" on the Sample board.
    nonisolated static let owner = "ari-linden"
    nonisolated static let ownerName = "Ari Linden"
    /// Everyone on the Sample board, you included, in board order on Today before it moves.
    nonisolated static let people = ["ines-volk", "odile-m", "ezra-q", owner, "bram-ott"]
    /// Listed in People but never loads, to show the missing-data placeholder. Screenshot fixture
    /// only; off on the Sample board.
    nonisolated static let failingCompetitor = "niko-vane"
    /// The prefix of `Options.extraPeople`: `sample-pal-01`, `sample-pal-02`, …
    nonisolated static let extraPersonPrefix = "sample-pal-"

    struct Options {
        /// That many more followed people (`sample-pal-01`, …) below everyone else, for a board long
        /// enough to scroll.
        var extraPeople = 0
        /// Adds `failingCompetitor` to the Acme organization.
        var includesFailingCompetitor = false
        /// Organizations that won't list their members for Committed, as People shows them.
        var restrictedOrganizations: [String]?
        /// This person trolls: 784 more today, far above their usual, so their row wears the troll
        /// face (screenshot fixture only).
        var trollPerson: String?
    }

    static func make(_ options: Options = Options(), now: @escaping @Sendable () -> Date = { Date() })
        -> CommittedServices {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineGitHub.self]
        let session = URLSession(configuration: config)
        let extras = (0..<options.extraPeople).map { extraPersonPrefix + String(format: "%02d", $0 + 1) }
        let organization = ["odile-m", "bram-ott"] + (options.includesFailingCompetitor ? [failingCompetitor] : [])
        let restricted = options.restrictedOrganizations
        return CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "sample"),
            contributions: SampleContributions(trollPerson: options.trollPerson),
            // Even a stray Connect GitHub on this graph stays on the phone.
            gitHubAuth: GitHubAuth(clientID: "sample", session: session),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: owner, sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ines-volk", "ezra-q"] + extras),
                    GitHubRosterSource(id: "org", title: "Acme", members: organization),
                ], updatedAt: now().addingTimeInterval(-240), restrictedOrganizations: restricted)
            },
            now: now
        )
    }

    /// Fixed Contributions per Window. Each person's first fetch sets today's baseline; from the
    /// second on, Ari Linden has 7 today and passes Ezra Q. Extra people count down from 39.
    private actor SampleContributions: ContributionsFetching {
        private var rounds: [String: Int] = [:]
        private let trollPerson: String?

        init(trollPerson: String? = nil) {
            self.trollPerson = trollPerson
        }

        func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
            async -> Result<StandingCounts, ContributionsError> {
            let round = rounds[username, default: 0]
            rounds[username] = round + 1
            let counts: [String: [ContributionWindow: Int]] = [
                "ines-volk": [.daily: 12, .weekly: 61, .monthly: 240],
                "odile-m": [.daily: 9, .weekly: 44, .monthly: 198],
                "ari-linden": [.daily: round == 0 ? 5 : 7, .weekly: 38, .monthly: 171],
                "ezra-q": [.daily: 6, .weekly: 52, .monthly: 160],
                "bram-ott": [.daily: 0, .weekly: 11, .monthly: 57],
            ]
            if username.hasPrefix(SampleServices.extraPersonPrefix),
               let number = Int(username.dropFirst(SampleServices.extraPersonPrefix.count)) {
                return .success(StandingCounts(contributions: max(0, 40 - number)))
            }
            guard let count = counts[username]?[window] else { return .failure(.network("offline")) }
            if username == trollPerson {
                let today = ContributionsParser.contributionCalendar().startOfDay(for: reference)
                return .success(StandingCounts(contributions: count + 784,
                                               burst: Burst(day: today, count: 784, usual: 102)))
            }
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
