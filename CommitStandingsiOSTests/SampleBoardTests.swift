import Foundation
import Testing
@testable import CommitStandingsiOS

/// The Sample board through the app model: try it from Connect GitHub, come back to it after a
/// relaunch, leave it, or replace it with a real board. Nothing on it leaves the device.
@MainActor
@Suite(.serialized)
struct SampleBoardTests {
    let clock = TestClock()
    let rosterCalls = RosterCalls()
    let activities = FakeLiveRankActivities()
    let relay = FakeLiveRankRelay()
    let widgets = RecordingWidgets()
    /// This test's own UserDefaults, standing in for `.standard` across "launches".
    let defaults: UserDefaults
    let realContributions = FakeContributions(["me": 3, "ada": 5])

    init() {
        defaults = UserDefaults(suiteName: "SampleBoardTests-\(UUID().uuidString)")!
        // A relay is configured for the real board, so the Sample board has to avoid it on purpose.
        relay.pushUpdates = .token
    }

    /// One launch of the app: a real, not-yet-connected graph (Keychain-like token in memory) whose
    /// hidden people persist in `defaults`, like the shipping app's.
    private func launch(token: String? = nil, gitHub: URLProtocol.Type = ApprovingGitHubProtocol.self) -> AppModel {
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [gitHub]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let rosterCalls = rosterCalls
        let services = CommittedServices(
            store: StandingsStore(
                persistence: InMemoryCompetitorPersistence(),
                hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence(defaults: defaults)
            ),
            credentials: InMemoryGitHubCredentialStore(token: token),
            contributions: realContributions,
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
        return AppModel(
            services: services,
            sampleServices: { [clock] in SampleServices.make(now: { clock.now }) },
            defaults: defaults,
            backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities,
            liveRankRelay: relay,
            widgets: widgets.publisher,
            now: { [clock] in clock.now }
        )
    }

    private func board(_ model: AppModel, _ window: ContributionWindow = .daily) -> [String] {
        Ranking.order(competitors: model.store.visibleCompetitors,
                      standings: model.store.standings(for: window), window: window)
            .map(\.competitor.username)
    }

    // MARK: Starting

    @Test func startingTheSampleBoardPublishesARankedBoard() async throws {
        let model = launch()
        #expect(model.mode == .notConnected)
        #expect(model.needsConnect)

        await model.startSampleBoard()

        #expect(model.mode == .sampleBoard)
        #expect(!model.needsConnect)
        #expect(board(model) == ["maya-chen", "priya-s", "devon-k", "sam-rivera", "lee-park"])
        let snapshot = try #require(widgets.last)
        #expect(snapshot.selfLogin == "sam-rivera")
        #expect(snapshot.top.map(\.login) == ["maya-chen", "priya-s", "devon-k", "sam-rivera", "lee-park"])
    }

    @Test func theSampleBoardSurvivesARelaunch() async {
        await launch().startSampleBoard()

        let relaunched = launch()
        #expect(relaunched.mode == .sampleBoard)
        #expect(!relaunched.needsConnect)
        await relaunched.sceneDidBecomeActive()
        #expect(board(relaunched) == ["maya-chen", "priya-s", "devon-k", "sam-rivera", "lee-park"])
    }

    // MARK: Leaving

    @Test func leavingReturnsToConnectGitHub() async {
        let model = launch()
        await model.startSampleBoard()
        #expect(!activities.running.isEmpty) // Live rank on the phone

        await model.leaveSampleBoard()

        #expect(model.mode == .notConnected)
        #expect(model.needsConnect)
        #expect(model.store.competitors.isEmpty)
        #expect(activities.running.isEmpty)
        #expect(widgets.published.last == .some(nil))
        #expect(launch().mode == .notConnected)
    }

    // MARK: Connecting

    @Test func connectingFromTheSampleBoardLeavesNoSampleState() async {
        let model = launch()
        await model.startSampleBoard()
        model.store.setHidden(true, username: "lee-park")
        await model.visibilityDidChange()

        await model.connectGitHub()

        #expect(model.mode == .connected)
        #expect(Set(model.store.competitors.map(\.username)) == ["me", "ada"])
        #expect(board(model) == ["ada", "me"])
        // The hide on the Sample board never reached the saved visibility preferences.
        #expect(UserDefaultsHiddenPeoplePersistence(defaults: defaults).load().isEmpty)
        #expect(widgets.last?.selfLogin == "me")
        #expect(launch(token: "gho_new").mode == .connected)
    }

    @Test func aDeclinedConnectFromTheSampleBoardStaysOnConnectGitHub() async {
        let model = launch(gitHub: DecliningGitHubProtocol.self)
        await model.startSampleBoard()
        model.selectedTab = .settings

        await model.connectGitHub()

        #expect(model.mode == .notConnected)
        #expect(model.needsConnect)
        #expect(model.auth.errorMessage == "The GitHub connection was declined.")
        #expect(model.selectedTab == .board)
        #expect(model.store.competitors.isEmpty)
        #expect(widgets.published.last == .some(nil))
        #expect(launch().mode == .notConnected)
    }

    // MARK: Nothing leaves the device

    @Test func nothingLeavesTheDeviceOnTheSampleBoard() async throws {
        let control = try #require(URL(string: "https://api.github.com/recorder-check/\(UUID().uuidString)"))
        GitHubTrafficRecorder.start()
        defer { GitHubTrafficRecorder.stop() }
        _ = try? await URLSession.shared.data(from: control)
        #expect(GitHubTrafficRecorder.requests.contains(control))

        let model = launch()
        await model.startSampleBoard()
        await model.pullToRefresh()
        model.store.selectedWindow = .weekly
        await model.windowDidChange()
        model.store.setHidden(true, username: "devon-k")
        await model.visibilityDidChange()
        await model.setLiveRankWindow(.monthly)
        model.sceneDidEnterBackground()
        await model.backgroundRefresh()
        await model.sceneDidBecomeActive()

        #expect(model.mode == .sampleBoard)
        #expect(board(model) == ["maya-chen", "priya-s", "sam-rivera", "lee-park"])
        #expect(await realContributions.total() == 0)
        #expect(rosterCalls.count == 0)
        // Live rank runs on the phone only: never registered with the relay, no push token asked.
        #expect(relay.configurations.compactMap { $0 }.isEmpty)
        #expect(!activities.startedPushUpdates.isEmpty)
        #expect(activities.startedPushUpdates.allSatisfy { $0 == .none })
        #expect(!model.isShowingLiveRankDisclosure)
        #expect(GitHubTrafficRecorder.unexpectedRequests.isEmpty)
    }
}

/// Shows a device code, then GitHub reports the person declined.
private final class DecliningGitHubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.url?.path == "/login/device/code"
            ? #"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
            : #"{"error":"access_denied"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
