#if DEBUG
import Foundation

/// Debug builds only: launch with `-ScreenshotFixture` to run the real app on a fixed, offline
/// board (no GitHub account, no network) for screenshots and visual checks:
///
///     xcrun simctl launch <udid> com.addisonk.CommitStandings.iOS -ScreenshotFixture
///
/// Optional, after `-ScreenshotFixture`: `-ScreenshotTab people|settings` opens on that tab,
/// `-ScreenshotHide <login>` hides that person before the first refresh (so Today still moves), and
/// `-LiveRankPayload <file.json>` shows a Live Activity push payload's content state in Live rank.
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

    /// The tab to open on, from `-ScreenshotTab board|people|settings`.
    static var requestedTab: AppTab? {
        guard isRequested else { return nil }
        switch value(after: "-ScreenshotTab") {
        case "board": return .board
        case "people": return .people
        case "settings": return .settings
        default: return nil
        }
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `-LiveRankPayload <file.json>`: a Live Activity push payload, the same file you'd give
    /// `xcrun simctl push` (`aps.content-state`). This machine's `simctl push` only delivers
    /// ordinary notifications, so the app applies the payload's content state itself: Live rank
    /// runs its real lifecycle, but shows the payload instead of the derived state. Add
    /// `-LiveRankAddActivity` to start another activity next to the running one (two activities
    /// share the Dynamic Island, so both show their minimal presentation).
    static func liveRankActivities(_ base: any LiveRankActivities) -> any LiveRankActivities {
        guard let path = value(after: "-LiveRankPayload"),
              let data = FileManager.default.contents(atPath: path),
              let payload = try? JSONDecoder().decode(LiveRankPayload.self, from: data) else { return base }
        let adds = ProcessInfo.processInfo.arguments.contains("-LiveRankAddActivity")
        return PayloadLiveRankActivities(base: base, state: payload.aps.contentState, hidesRunning: adds)
    }

    private struct LiveRankPayload: Decodable {
        struct APS: Decodable {
            let contentState: LiveRankState
            enum CodingKeys: String, CodingKey { case contentState = "content-state" }
        }
        let aps: APS
    }

    private final class PayloadLiveRankActivities: LiveRankActivities {
        let base: any LiveRankActivities
        let state: LiveRankState
        /// Add mode: the lifecycle sees only the activity this launch started, so it neither ends
        /// nor adopts the one already running.
        let hidesRunning: Bool
        private var started: Set<String> = []
        init(base: any LiveRankActivities, state: LiveRankState, hidesRunning: Bool) {
            self.base = base; self.state = state; self.hidesRunning = hidesRunning
        }

        var areActivitiesEnabled: Bool { base.areActivitiesEnabled }
        func current() -> [LiveRankActivity] {
            hidesRunning ? base.current().filter { started.contains($0.id) } : base.current()
        }
        func start(_ attributes: LiveRankAttributes, state _: LiveRankState, pushUpdates: LiveRankPushUpdates) throws
            -> LiveRankActivity {
            let activity = try base.start(attributes, state: state, pushUpdates: pushUpdates)
            started.insert(activity.id)
            return activity
        }
        func update(id: String, to _: LiveRankState) async { await base.update(id: id, to: state) }
        func end(id: String) async { await base.end(id: id) }
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
        let hide = value(after: "-ScreenshotHide")
        Task {
            await services.auth.refreshIdentity()
            if let hide {
                await services.roster.refresh(force: true)
                services.store.setHidden(true, username: hide)
            }
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
