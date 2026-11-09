import Foundation
import Testing
@testable import CommitStandingsiOS

/// Records any request to GitHub made through `URLSession.shared`, which every real network
/// client (`ContributionsClient`, `GitHubAccountClient`, `GitHubAuth`) uses by default, and fails
/// it as if offline. Sample services must never reach one.
final class GitHubTrafficRecorder: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [URL] = []
    nonisolated(unsafe) private static var users = 0

    static var requests: [URL] { lock.withLock { recorded } }

    /// Everything except the positive-control requests (`/recorder-check/…`) tests make to prove
    /// the recorder is listening. Suites run in parallel, so each test checks its own control with
    /// `requests.contains` and expects this to stay empty.
    static var unexpectedRequests: [URL] {
        requests.filter { !$0.path.hasPrefix("/recorder-check") }
    }

    /// Reference-counted, and never clears what's recorded, so suites running alongside each other
    /// can't unregister or reset it under one another.
    static func start() {
        lock.withLock {
            users += 1
            if users == 1 { URLProtocol.registerClass(GitHubTrafficRecorder.self) }
        }
    }

    static func stop() {
        lock.withLock {
            users -= 1
            if users == 0 { URLProtocol.unregisterClass(GitHubTrafficRecorder.self) }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Only GitHub hosts, so suites running alongside this one are unaffected.
        guard let host = request.url?.host else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let url = request.url { Self.lock.withLock { Self.recorded.append(url) } }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// The Sample board's data: the real app (`AppModel`, `CommittedServices`, `Ranking`) on built-in
/// people and counts, with nothing sent over the network.
/// Serialized: the recorder is process-wide.
@MainActor
@Suite(.serialized)
struct SampleServicesTests {
    let clock = TestClock()

    private func board(_ model: AppModel, _ window: ContributionWindow) -> [String] {
        Ranking.order(competitors: model.store.visibleCompetitors,
                      standings: model.store.standings(for: window), window: window)
            .map(\.competitor.username)
    }

    private func makeModel(_ options: SampleServices.Options = .init()) -> AppModel {
        let clock = clock
        return AppModel(services: SampleServices.make(options, now: { clock.now }),
                        backgroundTime: FakeBackgroundTime())
    }

    @Test func ranksEveryWindowWithoutTheNetwork() async throws {
        GitHubTrafficRecorder.start()
        defer { GitHubTrafficRecorder.stop() }
        // The recorder sees the shared session's GitHub traffic, so an empty list below means none.
        let control = try #require(URL(string: "https://api.github.com/recorder-check/\(UUID().uuidString)"))
        _ = try? await URLSession.shared.data(from: control)
        #expect(GitHubTrafficRecorder.requests.contains(control))

        let model = makeModel()
        #expect(!model.needsConnect)
        await model.sceneDidBecomeActive()
        #expect(model.auth.displayName == "Ari Linden")
        #expect(model.store.selfCompetitor?.username == "ari-linden")
        #expect(board(model, .daily) == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])

        model.store.selectedWindow = .weekly
        await model.windowDidChange()
        #expect(board(model, .weekly) == ["ines-volk", "ezra-q", "odile-m", "ari-linden", "bram-ott"])

        model.store.selectedWindow = .monthly
        await model.windowDidChange()
        #expect(board(model, .monthly) == ["ines-volk", "odile-m", "ari-linden", "ezra-q", "bram-ott"])

        #expect(GitHubTrafficRecorder.unexpectedRequests.isEmpty)
    }

    @Test func pullToRefreshMovesToday() async {
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(board(model, .daily) == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])
        await model.pullToRefresh()
        #expect(board(model, .daily) == ["ines-volk", "odile-m", "ari-linden", "ezra-q", "bram-ott"])
        #expect(model.refresh.rankDelta(for: "ari-linden") != nil) // the movement chevron
    }

    @Test func peopleSyncedFourMinutesAgo() async {
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(model.roster.snapshot?.updatedAt == clock.now.addingTimeInterval(-240))
    }

    /// The Sample board and the App Store screenshots show these logins with made-up counts, so
    /// none may be a real GitHub account. Each was checked to not exist on GitHub
    /// (`gh api users/<login>` returned 404) on 2026-11-09, as was `sample-pal-01` …
    /// `sample-pal-40`. Changing a name means checking the new one the same way first.
    @Test func samplePeopleAreMadeUpGitHubLogins() {
        #expect(SampleServices.owner == "ari-linden")
        #expect(SampleServices.ownerName == "Ari Linden")
        #expect(SampleServices.people == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])
        #expect(SampleServices.failingCompetitor == "niko-vane")
        #expect(SampleServices.extraPersonPrefix == "sample-pal-")
    }

    @Test func extraPeopleAreMadeUpTooAndLoad() async {
        let model = makeModel(.init(extraPeople: 2))
        await model.sceneDidBecomeActive()
        #expect(Set(board(model, .daily)) == Set(SampleServices.people + ["sample-pal-01", "sample-pal-02"]))
        #expect(model.store.standing(for: "sample-pal-01", window: .daily)?.contributions == 39)
        #expect(model.store.standing(for: "sample-pal-02", window: .daily)?.contributions == 38)
    }

    @Test func theFailingCompetitorIsAFixtureOption() async {
        let model = makeModel(.init(includesFailingCompetitor: true))
        await model.sceneDidBecomeActive()
        #expect(board(model, .daily).contains("niko-vane"))
        #expect(model.store.standing(for: "niko-vane", window: .daily)?.state == .failed("offline"))
    }
}
