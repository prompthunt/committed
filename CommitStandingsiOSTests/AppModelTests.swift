import Foundation
import Testing
@testable import CommitStandingsiOS

/// Counts contribution fetches per username and returns fixed counts, plus each person's calendar
/// when one is given (as the real client does).
actor FakeContributions: ContributionsFetching {
    private var counts: [String: Int]
    private var histories: [String: ContributionHistory]
    private(set) var calls: [String: Int] = [:]
    private(set) var windows: [ContributionWindow] = []

    init(_ counts: [String: Int], histories: [String: ContributionHistory] = [:]) {
        self.counts = counts
        self.histories = histories
    }

    func total() -> Int { calls.values.reduce(0, +) }

    /// A new count for `username`, as if they contributed since the last fetch.
    func set(_ username: String, _ count: Int) { counts[username] = count }

    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
        async -> Result<StandingCounts, ContributionsError> {
        calls[username, default: 0] += 1
        windows.append(window)
        guard let count = counts[username] else { return .failure(.userNotFound) }
        return .success(StandingCounts(contributions: count, history: histories[username]))
    }
}

final class RosterCalls: @unchecked Sendable { var count = 0 }

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 2_000_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class FakeBackgroundTime: BackgroundTimeProviding {
    private(set) var log: [String] = []
    private var next = 0
    func begin(_ name: String) -> Int { next += 1; log.append("begin \(name)"); return next }
    func end(_ token: Int) { log.append("end \(token)") }
}

/// Fake github.com for the device flow inside the iOS test host.
final class FakeGitHubProtocol: URLProtocol {
    nonisolated(unsafe) static var tokenResponse = #"{"error":"access_denied"}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.url?.path == "/login/device/code"
            ? #"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
            : Self.tokenResponse
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Serialized: the connect tests share `FakeGitHubProtocol`'s static response.
@MainActor
@Suite(.serialized)
struct AppModelTests {
    let clock = TestClock()
    let rosterCalls = RosterCalls()
    let background = FakeBackgroundTime()

    private func makeModel(signedIn: Bool = true, counts: [String: Int] = ["me": 3, "ada": 5],
                           histories: [String: ContributionHistory] = [:])
        -> (AppModel, FakeContributions) {
        let contributions = FakeContributions(counts, histories: histories)
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [FakeGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let rosterCalls = rosterCalls
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: signedIn ? "gho_test" : nil),
            contributions: contributions,
            gitHubAuth: GitHubAuth(clientID: "test", session: session, sleep: { _ in }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                rosterCalls.count += 1
                return GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada"]),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        return (AppModel(services: services, backgroundTime: background), contributions)
    }

    // MARK: Becoming active

    @Test func firstActivationLoadsPeopleAndContributions() async {
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()
        #expect(rosterCalls.count == 1)
        #expect(await contributions.calls == ["me": 1, "ada": 1])
        #expect(model.store.standing(for: "ada", window: .daily)?.contributions == 5)
    }

    /// Streaks on the Board come from the calendars a Refresh brings back, as of the app's clock.
    @Test func aRefreshShowsStreaksFromEachPersonsCalendar() async {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        func days(_ counts: [Int]) -> [String: Int] { // today first, then each day before
            var result: [String: Int] = [:]
            for (offset, count) in counts.enumerated() {
                let day = calendar.date(byAdding: .day, value: -offset, to: clock.now)!
                result[ContributionHistory.key(for: day, in: calendar)] = count
            }
            return result
        }
        let (model, _) = makeModel(counts: ["me": 3, "ada": 5], histories: [
            "me": ContributionHistory(days: days([3, 1, 2, 0, 4]), timeZone: utc),
            "ada": ContributionHistory(days: days([0, 5, 1, 1, 1, 0]), timeZone: utc),
        ])
        #expect(model.refresh.streak(for: "me") == nil)
        await model.sceneDidBecomeActive()
        #expect(model.refresh.streak(for: "me") == 3)
        #expect(model.refresh.streak(for: "ada") == 4) // nothing yet today: alive from yesterday
    }

    @Test func becomingActiveAgainWithFreshDataDoesNotRefresh() async {
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()
        model.sceneDidEnterBackground()
        clock.advance(90)
        await model.sceneDidBecomeActive()
        #expect(await contributions.total() == 2)
    }

    @Test func becomingActiveWithStaleDataRefreshes() async {
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()
        model.sceneDidEnterBackground()
        clock.advance(150)
        await model.sceneDidBecomeActive()
        #expect(await contributions.total() == 4)
        #expect(model.refresh.lastReason == .becameActive)
    }

    @Test func signedOutActivationFetchesNothing() async {
        let (model, contributions) = makeModel(signedIn: false)
        #expect(model.needsConnect)
        await model.sceneDidBecomeActive()
        #expect(await contributions.total() == 0)
        #expect(rosterCalls.count == 0)
    }

    @Test func timerPausesInTheBackgroundAndResumesWhenActive() async {
        let (model, _) = makeModel()
        #expect(model.refresh.isTimerRunning)
        model.sceneDidEnterBackground()
        #expect(!model.refresh.isTimerRunning)
        await model.sceneDidBecomeActive()
        #expect(model.refresh.isTimerRunning)
    }

    // MARK: Window switching

    @Test func switchingToAnUnloadedWindowFetchesIt() async {
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()
        model.store.selectedWindow = .weekly
        await model.windowDidChange()
        #expect(await contributions.windows.filter { $0 == .weekly }.count == 2)
        #expect(model.store.standing(for: "me", window: .weekly)?.contributions == 3)
    }

    @Test func switchingBackToAFreshWindowShowsCachedNumbersWithoutFetching() async {
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()
        model.store.selectedWindow = .weekly
        await model.windowDidChange()
        model.store.selectedWindow = .daily
        await model.windowDidChange()
        #expect(await contributions.total() == 4)
        #expect(model.store.standing(for: "ada", window: .daily)?.contributions == 5)
    }

    // MARK: Pull to refresh

    @Test func pullToRefreshReloadsPeopleAndContributions() async {
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()
        clock.advance(10) // well inside the roster's 15-minute throttle
        await model.pullToRefresh()
        #expect(rosterCalls.count == 2)
        #expect(await contributions.total() == 4)
        #expect(model.refresh.lastReason == .manual)
    }

    // MARK: Deep links

    @Test func boardLinkOpensTheBoardOnTheRequestedWindow() {
        let (model, _) = makeModel()
        model.selectedTab = .settings
        #expect(model.open(URL(string: "committed://board?window=monthly")!))
        #expect(model.selectedTab == .board)
        #expect(model.store.selectedWindow == .monthly)
    }

    @Test func unrelatedLinksChangeNothing() {
        let (model, _) = makeModel()
        model.selectedTab = .people
        #expect(!model.open(URL(string: "https://github.com/login/device")!))
        #expect(model.selectedTab == .people)
        #expect(model.store.selectedWindow == .daily)
    }

    // MARK: Connect GitHub

    @Test func connectingHoldsBackgroundTimeForTheWholeDeviceFlow() async {
        FakeGitHubProtocol.tokenResponse = #"{"error":"access_denied"}"#
        let (model, _) = makeModel(signedIn: false)
        await model.connectGitHub()
        #expect(background.log == ["begin Connect GitHub", "end 1"])
        #expect(model.auth.errorMessage == "The GitHub connection was declined.")
        #expect(model.needsConnect)
    }

    @Test func approvedConnectLeavesTheConnectScreenAndLoadsTheBoard() async {
        FakeGitHubProtocol.tokenResponse = #"{"access_token":"gho_new"}"#
        let (model, contributions) = makeModel(signedIn: false)
        await model.connectGitHub()
        #expect(!model.needsConnect)
        #expect(model.store.selfCompetitor?.username == "me")
        #expect(await contributions.calls == ["me": 1, "ada": 1])
    }
}
